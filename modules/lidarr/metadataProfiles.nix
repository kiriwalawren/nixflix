{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.lidarr;
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  mkWaitForApiScript = import ../arr-common/mkWaitForApiScript.nix { inherit lib pkgs; };

  inherit (import ./metadataAlbumTypes.nix)
    primaryAlbumTypeDefs
    secondaryAlbumTypeDefs
    releaseStatusDefs
    ;

  # Builds a submodule type with one `bool` option (default false) per entry in `defs`.
  mkEnableFlagsType =
    defs:
    types.submodule {
      options = listToAttrs (
        map (
          d:
          nameValuePair d.option (mkOption {
            type = types.bool;
            default = false;
            description = ''Whether the "${d.name}" type is allowed.'';
          })
        ) defs
      );
    };

  # Expands an enable-flags attrset back into the `{ albumType = { id; name; }; allowed; }` /
  # `{ releaseStatus = { id; name; }; allowed; }` list shape Lidarr's API expects.
  expandAlbumTypes =
    defs: flags:
    map (d: {
      albumType = {
        inherit (d) id name;
      };
      allowed = flags.${d.option};
    }) defs;
  expandReleaseStatuses =
    defs: flags:
    map (d: {
      releaseStatus = {
        inherit (d) id name;
      };
      allowed = flags.${d.option};
    }) defs;

  primaryAlbumTypesType = mkEnableFlagsType primaryAlbumTypeDefs;
  secondaryAlbumTypesType = mkEnableFlagsType secondaryAlbumTypeDefs;
  releaseStatusesType = mkEnableFlagsType releaseStatusDefs;

  defaultMetadataProfile = {
    name = "Standard";
    primaryAlbumTypes = {
      enableSingle = true;
      enableEP = true;
      enableAlbum = true;
    };
    secondaryAlbumTypes = {
      enableStudio = true;
      enableSoundtrack = true;
      enableRemix = true;
      enableLive = true;
      enableCompilation = true;
    };
    releaseStatuses = {
      enableOfficial = true;
    };
    id = 1;
  };

  metadataProfileType = types.submodule {
    freeformType = types.attrsOf types.anything;
    options = {
      name = mkOption {
        type = types.str;
        description = "Name of the metadata profile, shown in the Lidarr UI. Used to match against existing profiles.";
      };
      primaryAlbumTypes = mkOption {
        type = primaryAlbumTypesType;
        default = { };
        description = "Enable flags for which album types are allowed as an artist's primary album type.";
      };
      secondaryAlbumTypes = mkOption {
        type = secondaryAlbumTypesType;
        default = { };
        description = "Enable flags for which album types are allowed as secondary album types.";
      };
      releaseStatuses = mkOption {
        type = releaseStatusesType;
        default = { };
        description = "Enable flags for which release statuses are allowed when selecting releases.";
      };
      id = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          Lidarr's internal id for this profile. Ignored when reconciling — profiles are matched by
          `name`, and the real instance id is substituted automatically — so this rarely needs to be set.
        '';
      };
    };
  };
in
{
  options.nixflix.lidarr.config.metadataProfiles = mkOption {
    type = types.listOf metadataProfileType;
    default = [ defaultMetadataProfile ];
    description = ''
      List of metadata profiles to configure via the API /metadataprofile endpoint.
      Each profile is matched and reconciled by `name` (Lidarr assigns `id` per-instance).

      Defaults to a single "Standard" profile. At least one metadata profile must be present.
    '';
  };

  config = mkIf (config.nixflix.enable && cfg.enable) (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.config.metadataProfiles != [ ];
          message = "nixflix.lidarr.config.metadataProfiles must contain at least one metadata profile.";
        }
      ];
    }
    (mkIf (cfg.config.apiKey != null) {
      systemd.services."lidarr-metadataprofiles" = {
        description = "Configure Lidarr metadata profiles via API";
        after = [ "lidarr-config.service" ] ++ config.nixflix.serviceDependencies;
        requires = [ "lidarr-config.service" ] ++ config.nixflix.serviceDependencies;
        before = [ "lidarr-rootfolders.service" ];
        requiredBy = [ "lidarr-rootfolders.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = mkWaitForApiScript "lidarr" cfg.config;
        };

        script = ''
          set -eu

          BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

          echo "Fetching existing metadata profiles..."
          METADATA_PROFILES=$(${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/metadataprofile";
              extraArgs = "-Sf";
            }
          } 2>/dev/null)

          CONFIGURED_NAMES=$(cat <<'EOF'
          ${builtins.toJSON (map (p: p.name) cfg.config.metadataProfiles)}
          EOF
          )

          echo "Removing metadata profiles not in configuration..."
          echo "$METADATA_PROFILES" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r profile; do
            PROFILE_NAME=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.name')
            PROFILE_ID=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.id')

            if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$PROFILE_NAME" 'index($name)' >/dev/null 2>&1; then
              echo "Deleting metadata profile not in config: $PROFILE_NAME (ID: $PROFILE_ID)"
              ${
                mkSecureCurl cfg.config.apiKey {
                  url = "$BASE_URL/metadataprofile/$PROFILE_ID";
                  method = "DELETE";
                  extraArgs = "-Sf";
                }
              } >/dev/null 2>&1 || echo "Warning: Failed to delete metadata profile $PROFILE_NAME (may be in use)"
            fi
          done

          ${concatMapStringsSep "\n" (
            profileConfig:
            let
              profileForApi = profileConfig // {
                primaryAlbumTypes = expandAlbumTypes primaryAlbumTypeDefs profileConfig.primaryAlbumTypes;
                secondaryAlbumTypes = expandAlbumTypes secondaryAlbumTypeDefs profileConfig.secondaryAlbumTypes;
                releaseStatuses = expandReleaseStatuses releaseStatusDefs profileConfig.releaseStatuses;
              };
              profileJson = builtins.toJSON profileForApi;
              profileName = profileConfig.name;
            in
            ''
              echo "Processing metadata profile: ${profileName}"

              EXISTING_PROFILE=$(echo "$METADATA_PROFILES" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg profileName} '.[] | select(.name == $name) | @json' || echo "")

              if [ -n "$EXISTING_PROFILE" ]; then
                EXISTING_ID=$(echo "$EXISTING_PROFILE" | ${pkgs.jq}/bin/jq -r '.id')
                echo "Metadata profile ${profileName} already exists (ID: $EXISTING_ID), updating..."
                UPDATED_PROFILE=$(echo ${escapeShellArg profileJson} | ${pkgs.jq}/bin/jq --argjson id "$EXISTING_ID" '.id = $id')
                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/metadataprofile/$EXISTING_ID";
                    method = "PUT";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$UPDATED_PROFILE";
                    extraArgs = "-Sf";
                  }
                } > /dev/null
                echo "Metadata profile ${profileName} updated"
              else
                echo "Metadata profile ${profileName} does not exist, creating..."
                NEW_PROFILE=$(echo ${escapeShellArg profileJson} | ${pkgs.jq}/bin/jq 'del(.id)')
                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/metadataprofile";
                    method = "POST";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$NEW_PROFILE";
                    extraArgs = "-Sf";
                  }
                } > /dev/null
                echo "Metadata profile ${profileName} created"
              fi
            ''
          ) cfg.config.metadataProfiles}

          echo "Lidarr metadata profiles configuration complete"
        '';
      };
    })
  ]);
}
