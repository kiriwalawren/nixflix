{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.lidarr;
  mp = cfg.config.metadataProvider;
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  mkWaitForApiScript = import ../arr-common/mkWaitForApiScript.nix { inherit lib pkgs; };
in
{
  options.nixflix.lidarr.config.metadataProvider = {
    metadataSource = mkOption {
      type = types.str;
      default = "";
      description = "Custom metadata server URL. Leave empty to use Lidarr's default metadata source.";
    };

    writeAudioTags = mkOption {
      type = types.enum [
        "no"
        "newFiles"
        "allFiles"
        "sync"
      ];
      default = "sync";
      description = ''
        When to write metadata tags to audio files:

        - `"no"`: never write tags.
        - `"newFiles"`: write tags when a file is imported via a download client or the Manual Import screen.
        - `"allFiles"`: write tags once, on import.
        - `"sync"`: write tags on import and rewrite them whenever the MusicBrainz data changes.
      '';
    };

    scrubAudioTags = mkOption {
      type = types.bool;
      default = true;
      description = "Remove existing tags from audio files that Lidarr does not manage.";
    };

    embedCoverArt = mkOption {
      type = types.bool;
      default = true;
      description = "Embed album cover art into audio files when writing tags.";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable && cfg.config.apiKey != null) {
    systemd.services."lidarr-metadataprovider" = {
      description = "Configure Lidarr metadata provider via API";
      after = [ "lidarr-config.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "lidarr-config.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = mkWaitForApiScript "lidarr" cfg.config;
      };

      script = ''
        set -eu

        BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

        echo "Fetching current metadata provider configuration..."
        CURRENT_CONFIG=$(${
          mkSecureCurl cfg.config.apiKey {
            url = "$BASE_URL/config/metadataprovider";
            extraArgs = "-Sf";
          }
        } 2>/dev/null)

        if [ -z "$CURRENT_CONFIG" ]; then
          echo "Failed to fetch metadata provider configuration"
          exit 1
        fi

        CONFIG_ID=$(echo "$CURRENT_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

        DESIRED=$(${pkgs.jq}/bin/jq -n \
          --arg metadataSource ${escapeShellArg mp.metadataSource} \
          --arg writeAudioTags ${escapeShellArg mp.writeAudioTags} \
          '{
            metadataSource: $metadataSource,
            writeAudioTags: $writeAudioTags,
            scrubAudioTags: ${boolToString mp.scrubAudioTags},
            embedCoverArt: ${boolToString mp.embedCoverArt}
          }')

        NEW_CONFIG=$(${pkgs.jq}/bin/jq -n \
          --argjson current "$CURRENT_CONFIG" \
          --argjson desired "$DESIRED" \
          '$current * $desired')

        echo "Updating Lidarr metadata provider configuration..."
        PUT_STATUS=$(${
          mkSecureCurl cfg.config.apiKey {
            url = "$BASE_URL/config/metadataprovider/$CONFIG_ID";
            method = "PUT";
            headers = {
              "Content-Type" = "application/json";
            };
            data = "$NEW_CONFIG";
            extraArgs = ''-So /tmp/put_response -w "%{http_code}"'';
          }
        })
        if [ "$PUT_STATUS" -ge 400 ]; then
          echo "PUT failed (HTTP $PUT_STATUS):"
          cat /tmp/put_response
          exit 1
        fi

        echo "Lidarr metadata provider configuration complete"
      '';
    };
  };
}
