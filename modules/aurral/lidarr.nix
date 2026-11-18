{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  inherit (config) nixflix;
  cfg = nixflix.aurral;

  apiUtil = import ./apiUtil.nix { inherit lib pkgs cfg; };
  inherit (apiUtil) apiCall;

  lidarrJq = secrets.mkJqSecretArgs { lidarrApiKey = cfg.settings.lidarr.apiKey; };

  configureLidarr = ''
    echo "Saving Lidarr connection..."
    LIDARR_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      ${lidarrJq.flagsString} \
      --arg url ${escapeShellArg cfg.settings.lidarr.url} \
      --arg defaultMonitorOption ${escapeShellArg cfg.settings.lidarr.defaultMonitorOption} \
      --arg externalUrl ${escapeShellArg cfg.settings.lidarr.externalUrl} \
      '{
        integrations: {
          lidarr: {
            enabled: true,
            url: $url,
            externalUrl: $externalUrl,
            apiKey: ${lidarrJq.refs.lidarrApiKey},
            defaultMonitorOption: $defaultMonitorOption,
            searchOnAdd: ${boolToString cfg.settings.lidarr.searchOnAdd}
          }
        }
      }')
    check_response "save Lidarr connection" "$(${apiCall "POST" "/settings" "$LIDARR_PAYLOAD"})"

    check_response "fetch Lidarr quality profiles" "$(${
      apiCall "GET" "/settings/lidarr/profiles" null
    })"
    QUALITY_PROFILE_ID=$(echo "$BODY" | ${pkgs.jq}/bin/jq -r '.[0].id // empty')

    check_response "fetch Lidarr metadata profiles" "$(${
      apiCall "GET" "/settings/lidarr/metadata-profiles" null
    })"
    METADATA_PROFILE_ID=$(echo "$BODY" | ${pkgs.jq}/bin/jq -r '[.[] | select(.name != "None")][0].id // empty')

    if [ -z "$QUALITY_PROFILE_ID" ] || [ -z "$METADATA_PROFILE_ID" ]; then
      echo "Could not determine Lidarr quality/metadata profile IDs" >&2
      exit 1
    fi
    echo "Using Lidarr quality profile $QUALITY_PROFILE_ID and metadata profile $METADATA_PROFILE_ID"

    PROFILES_PAYLOAD=$(${pkgs.jq}/bin/jq -n \
      --argjson qualityProfileId "$QUALITY_PROFILE_ID" \
      --argjson metadataProfileId "$METADATA_PROFILE_ID" \
      --arg rootFolderPath ${escapeShellArg (toString cfg.settings.lidarr.rootFolderPath)} \
      '{ integrations: { lidarr: ({ qualityProfileId: $qualityProfileId, metadataProfileId: $metadataProfileId }
        + (if $rootFolderPath == "" then {} else { rootFolderPath: $rootFolderPath } end)) } }')
    check_response "save Lidarr profiles" "$(${apiCall "POST" "/settings" "$PROFILES_PAYLOAD"})"
  '';

  disableLidarr = ''
    echo "Disabling Lidarr integration..."
    check_response "disable Lidarr" "$(${
      apiCall "POST" "/settings"
        ''{"integrations":{"lidarr":{"enabled":false,"rootFolderPath":null,"rootFolderPaths":[]}}}''
    })"
  '';
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.aurral-lidarr = {
      description = "Configure Aurral's Lidarr integration";
      after = [ "aurral-setup.service" ] ++ optional nixflix.lidarr.enable "lidarr-config.service";
      requires = [ "aurral-setup.service" ] ++ optional nixflix.lidarr.enable "lidarr-config.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        ${apiUtil.preamble}

        ${if nixflix.lidarr.enable then configureLidarr else disableLidarr}
      '';
    };
  };
}
