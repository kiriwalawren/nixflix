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
  syncMode = import ../../../lib/sync-mode.nix { inherit lib pkgs; };
  inherit (syncMode) indentRest;

  maintainerrUrl = "http://${cfg.connectionAddress}:${toString cfg.port}";
  jobsJson = builtins.toJSON cfg.settings.jobs;

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

  # Refuse mode reads the live servers into their own variable at the top of
  # the unit, because the Jellyfin/Seerr settings are POSTed before the
  # *arr servers are synced. ARR_CURRENT is still fetched where it always was.
  arrLiveVar = type: "ARR_LIVE_${toUpper type}";

  mkArrPrune =
    type: servers:
    let
      declaredNames = builtins.toJSON (map (s: s.serverName) servers);
      mode = cfg.syncMode.${type};
    in
    syncMode.mkPrune {
      inherit mode;
      unit = "maintainerr-settings";
      what = "${type} servers";
      option = "nixflix.maintainerr.syncMode.${type}";
      live = if mode == "refuse" then arrLiveVar type else "ARR_CURRENT";
      declared = map (s: s.serverName) servers;
      key = ".serverName";
      onDelete = ''
        TO_DELETE=$(echo "$ARR_CURRENT" | ${pkgs.jq}/bin/jq -r \
          --argjson declared '${declaredNames}' \
          '.[] | select(.serverName as $n | ($declared | index($n)) == null) | .id')
        for ID in $TO_DELETE; do
          echo "  Deleting undeclared ${type} (id=$ID)..."
          ${pkgs.curl}/bin/curl -s -X DELETE \
            "${maintainerrUrl}/api/settings/${type}/$ID" > /dev/null
        done
      '';
    };

  arrTypes = [
    "radarr"
    "sonarr"
  ];

  refuseTypes = filter (type: cfg.syncMode.${type} == "refuse") arrTypes;

  # POST media-server/switch from anything but Jellyfin clears every rule group
  # (and its rules), collection, collection media and log, and exclusion
  # (Maintainerr's MediaServerSwitchService.clearMediaServerData). "delete"
  # keeps nixflix's historical unconditional switch; keep/refuse first ask the
  # preview endpoint what it would clear and only switch when that is nothing.
  mediaServerMode = cfg.syncMode.mediaServer;
  mediaServerOption = "nixflix.maintainerr.syncMode.mediaServer";

  switchToJellyfin = removeSuffix "\n" ''
    echo "Switching media server type to Jellyfin..."
    ${pkgs.curl}/bin/curl -s -X POST \
      -H "Content-Type: application/json" \
      -d '{"targetServerType":"jellyfin"}' \
      "${maintainerrUrl}/api/settings/media-server/switch" \
      | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null
  '';

  # Sets MEDIA_SERVER_TYPE and MS_CLEARS (what a switch would clear, "" for
  # nothing). A malformed answer aborts the unit under `set -e`.
  inspectSwitch = ''
    MEDIA_SERVER_TYPE=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings" \
      | ${pkgs.jq}/bin/jq -r '.media_server_type // ""')
    MS_CLEARS=""
    if [ "$MEDIA_SERVER_TYPE" != "jellyfin" ]; then
      MS_PREVIEW=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/media-server/switch/preview/jellyfin")
      MS_RULE_GROUPS=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/rules")
      MS_CLEARS=$(${pkgs.jq}/bin/jq -nr --argjson p "$MS_PREVIEW" --argjson r "$MS_RULE_GROUPS" '
        if ($r | type) != "array" or ($p.dataToBeCleared | type) != "object" then
          error("unexpected answer from the Maintainerr API")
        else
          [ ($r | length), "rule groups (with their rules)" ],
          [ $p.dataToBeCleared.collections, "collections" ],
          [ $p.dataToBeCleared.collectionMedia, "collection media items" ],
          [ $p.dataToBeCleared.exclusions, "exclusions" ],
          [ $p.dataToBeCleared.collectionLogs, "collection logs" ]
          | select(.[0] > 0) | "\(.[0]) \(.[1])"
        end' | paste -sd, - | sed 's/,/, /g')
    fi
  '';

  mediaServerGuard = ''
    # nixflix-sync-guard: maintainerr-settings media server switch
    ${inspectSwitch}
    if [ -n "$MS_CLEARS" ]; then
      {
        echo "nixflix: maintainerr-settings: refusing to sync: Maintainerr uses media server '$MEDIA_SERVER_TYPE', and switching it to Jellyfin clears $MS_CLEARS (${mediaServerOption} = \"refuse\"). Nothing was changed."
        echo "nixflix: switch it in the Maintainerr UI, which can migrate the rules, or set ${mediaServerOption} to \"delete\"."
      } >&2
      NIXFLIX_SYNC_REFUSED=1
    fi
  '';

  mediaServerSwitch =
    if mediaServerMode == "delete" then
      ''
        MEDIA_SERVER_TYPE=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings" \
          | ${pkgs.jq}/bin/jq -r '.media_server_type')
        if [ "$MEDIA_SERVER_TYPE" != "jellyfin" ]; then
          ${syncMode.indentRest 2 switchToJellyfin}
        fi
      ''
    else if mediaServerMode == "refuse" then
      # The guard ran before the checkpoint, so nothing is cleared here.
      ''
        if [ "$MEDIA_SERVER_TYPE" != "jellyfin" ]; then
          ${syncMode.indentRest 2 switchToJellyfin}
        fi
      ''
    else
      ''
        ${syncMode.indentRest 2 inspectSwitch}
        if [ "$MEDIA_SERVER_TYPE" != "jellyfin" ]; then
          if [ -n "$MS_CLEARS" ]; then
            echo "nixflix: maintainerr-settings: not switching media server '$MEDIA_SERVER_TYPE' to Jellyfin: that clears $MS_CLEARS (${mediaServerOption} = \"keep\")"
          else
            ${syncMode.indentRest 6 switchToJellyfin}
            MEDIA_SERVER_TYPE=jellyfin
          fi
        fi
      '';

  jellyfinSettings = ''

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

  '';

  # keep may decline the switch; the Jellyfin connection is then not set up,
  # and maintainerr-rules skips itself (it asks Maintainerr, see rules/).
  jellyfinSettingsIfOnJellyfin = ''

    if [ "$MEDIA_SERVER_TYPE" = "jellyfin" ]; then
      ${indentRest 2 (removePrefix "\n" jellyfinSettings)}
    else
      echo "nixflix: maintainerr-settings: Maintainerr stays on media server '$MEDIA_SERVER_TYPE', so the Jellyfin connection is not set up (${mediaServerOption} = \"keep\")"
    fi

  '';

  refuseGuards = optionalString (refuseTypes != [ ] || mediaServerMode == "refuse") (
    concatMapStrings (type: ''
      ${arrLiveVar type}=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/${type}")
    '') refuseTypes
    + concatMapStrings (type: (mkArrPrune type cfg.settings.${type}).guard) refuseTypes
    + optionalString (mediaServerMode == "refuse") mediaServerGuard
    + syncMode.refuseCheckpoint
    + "\n\n"
  );

  mkArrTypeScript = type: servers: ''
    echo "Syncing ${type} servers..."
    ARR_CURRENT=$(${pkgs.curl}/bin/curl -s "${maintainerrUrl}/api/settings/${type}")

    ${(mkArrPrune type servers).prune}
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
      after = [
        "maintainerr.service"
      ]
      ++ optional config.nixflix.jellyfin.enable "jellyfin-api-key.service"
      ++ optional config.nixflix.radarr.enable "radarr-config.service"
      ++ optional config.nixflix.sonarr.enable "sonarr-config.service"
      ++ optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
      ++ optional config.nixflix.seerr.enable "seerr-setup.service";
      requires = [
        "maintainerr.service"
      ]
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

          ''
          + refuseGuards
          + mediaServerSwitch
          + (if mediaServerMode == "keep" then jellyfinSettingsIfOnJellyfin else jellyfinSettings)
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

            echo "Applying Seerr settings..."
            ${pkgs.curl}/bin/curl -s -X POST \
              -H "Content-Type: application/json" \
              --data-binary "$(${pkgs.jq}/bin/jq -n \
                --arg url "$SEERR_URL" \
                --arg apiKey "$SEERR_API_KEY" \
                '{url: $url, api_key: $apiKey}')" \
              "${maintainerrUrl}/api/settings/seerr" \
              | ${pkgs.jq}/bin/jq -e '.status == "OK"' > /dev/null

          ''
          + mkArrTypeScript "radarr" cfg.settings.radarr
          + mkArrTypeScript "sonarr" cfg.settings.sonarr
          + ''
            echo "Applying job schedules..."
            ${pkgs.curl}/bin/curl -sf -X PATCH \
              -H "Content-Type: application/json" \
              --data-binary ${escapeShellArg jobsJson} \
              "${maintainerrUrl}/api/settings" \
              | ${pkgs.jq}/bin/jq -e '. != null' > /dev/null

            echo "Maintainerr settings configured successfully."
          ''
        );
      };
    };
  };
}
