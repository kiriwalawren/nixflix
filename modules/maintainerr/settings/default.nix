{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.maintainerr;
  secrets = import ../../../lib/secrets { inherit lib; };

  maintainerrUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";

  mkArrServerScript =
    type: server:
    let
      apiKeyVal = secrets.toShellValue server.apiKey;
    in
    ''
      echo "  Configuring ${server.serverName}..."
      ARR_API_KEY=${apiKeyVal}
      EXISTING_ID=$(echo "$ARR_CURRENT" \
        | ${pkgs.jq}/bin/jq -r --arg name "${server.serverName}" \
            '[ .[] | select(.serverName == $name) | .id ] | .[0] // empty')
      if [ -n "$EXISTING_ID" ]; then
        ${pkgs.curl}/bin/curl -s -X PUT \
          -H "Content-Type: application/json" \
          --data-binary "$(${pkgs.jq}/bin/jq -n \
            --arg url "${server.url}" \
            --arg serverName "${server.serverName}" \
            --arg apiKey "$ARR_API_KEY" \
            --argjson id "$EXISTING_ID" \
            '{url: $url, serverName: $serverName, apiKey: $apiKey, id: $id}')" \
          "${maintainerrUrl}/api/settings/${type}/$EXISTING_ID" \
          | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null
      else
        ${pkgs.curl}/bin/curl -s -X POST \
          -H "Content-Type: application/json" \
          --data-binary "$(${pkgs.jq}/bin/jq -n \
            --arg url "${server.url}" \
            --arg serverName "${server.serverName}" \
            --arg apiKey "$ARR_API_KEY" \
            '{url: $url, serverName: $serverName, apiKey: $apiKey}')" \
          "${maintainerrUrl}/api/settings/${type}" \
          | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null
      fi
    '';

  mkArrTypeScript =
    type: servers:
    let
      declaredNames = builtins.toJSON (map (s: s.serverName) servers);
    in
    ''
      echo "Syncing ${type} servers..."
      ARR_CURRENT=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/${type}")

      TO_DELETE=$(echo "$ARR_CURRENT" | ${pkgs.jq}/bin/jq -r \
        --argjson declared '${declaredNames}' \
        '.[] | select(.serverName as $n | ($declared | index($n)) == null) | .id')
      for ID in $TO_DELETE; do
        echo "  Deleting undeclared ${type} (id=$ID)..."
        ${pkgs.curl}/bin/curl -s -X DELETE \
          "${maintainerrUrl}/api/settings/${type}/$ID" > /dev/null
      done

      ${concatMapStrings (mkArrServerScript type) servers}
    '';

in
{
  imports = [ ./options.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.nixflix.jellyfin.enable;
        message = "nixflix.maintainerr.enable = true requires nixflix.jellyfin.enable = true.";
      }
    ];

    systemd.services.maintainerr-settings = {
      description = "Configure Maintainerr settings via API";
      after =
        [
          "maintainerr.service"
          "network-online.target"
        ]
        ++ optional config.nixflix.jellyfin.enable "jellyfin-api-key.service"
        ++ optional config.nixflix.radarr.enable "radarr-config.service"
        ++ optional config.nixflix.sonarr.enable "sonarr-config.service"
        ++ optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
        ++ optional config.nixflix.seerr.enable "seerr-setup.service";
      requires =
        [ "maintainerr.service" ]
        ++ optional config.nixflix.jellyfin.enable "jellyfin-api-key.service"
        ++ optional config.nixflix.radarr.enable "radarr-config.service"
        ++ optional config.nixflix.sonarr.enable "sonarr-config.service"
        ++ optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
        ++ optional config.nixflix.seerr.enable "seerr-setup.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "maintainerr-settings" (
          ''
            set -euo pipefail

            echo "Waiting for Maintainerr to become available..."
            READY=false
            for i in $(seq 1 120); do
              if ${pkgs.curl}/bin/curl -sf "${maintainerrUrl}/api/settings" > /dev/null 2>&1; then
                READY=true
                break
              fi
              sleep 1
            done
            if [ "$READY" != "true" ]; then
              echo "Maintainerr did not become ready after 120s" >&2
              exit 1
            fi

            MEDIA_SERVER_TYPE=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings" \
              | ${pkgs.jq}/bin/jq -r '.media_server_type')
            if [ "$MEDIA_SERVER_TYPE" != "jellyfin" ]; then
              echo "Switching media server type to Jellyfin..."
              ${pkgs.curl}/bin/curl -s -X POST \
                -H "Content-Type: application/json" \
                -d '{"targetServerType":"jellyfin"}' \
                "${maintainerrUrl}/api/settings/media-server/switch" \
                | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null
            fi

            JELLYFIN_URL=${secrets.toShellValue cfg.settings.jellyfin.jellyfin_url}
            JELLYFIN_API_KEY=${secrets.toShellValue cfg.settings.jellyfin.jellyfin_api_key}

            echo "Testing Jellyfin connection..."
            JELLYFIN_USER_ID=$(${pkgs.curl}/bin/curl -s -X POST \
              -H "Content-Type: application/json" \
              --data-binary "$(${pkgs.jq}/bin/jq -n \
                --arg url "$JELLYFIN_URL" \
                --arg apiKey "$JELLYFIN_API_KEY" \
                '{jellyfin_url: $url, jellyfin_api_key: $apiKey}')" \
              "${maintainerrUrl}/api/settings/jellyfin/test" \
              | ${pkgs.jq}/bin/jq -e -r '.users[0].id')

            echo "Applying Jellyfin settings..."
            ${pkgs.curl}/bin/curl -s -X POST \
              -H "Content-Type: application/json" \
              --data-binary "$(${pkgs.jq}/bin/jq -n \
                --arg url "$JELLYFIN_URL" \
                --arg apiKey "$JELLYFIN_API_KEY" \
                --arg userId "$JELLYFIN_USER_ID" \
                '{jellyfin_url: $url, jellyfin_api_key: $apiKey, jellyfin_user_id: $userId}')" \
              "${maintainerrUrl}/api/settings/jellyfin" \
              | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null

          ''
          + optionalString config.nixflix.seerr.enable ''
            SEERR_URL=${secrets.toShellValue cfg.settings.seerr.url}
            SEERR_API_KEY=${secrets.toShellValue cfg.settings.seerr.api_key}

            echo "Testing Seerr connection..."
            ${pkgs.curl}/bin/curl -s -X POST \
              -H "Content-Type: application/json" \
              --data-binary "$(${pkgs.jq}/bin/jq -n \
                --arg url "$SEERR_URL" \
                --arg apiKey "$SEERR_API_KEY" \
                '{url: $url, api_key: $apiKey}')" \
              "${maintainerrUrl}/api/settings/test/seerr" \
              | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null

          ''
          + mkArrTypeScript "radarr" cfg.settings.radarr
          + mkArrTypeScript "sonarr" cfg.settings.sonarr
          + ''
            echo "Maintainerr settings configured successfully."
          ''
        );
      };
    };
  };
}
