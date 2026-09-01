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

  defaultMetadataProfile = {
    name = "Standard";
    primaryAlbumTypes = [
      {
        albumType = {
          id = 2;
          name = "Single";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 4;
          name = "Other";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 1;
          name = "EP";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 3;
          name = "Broadcast";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 0;
          name = "Album";
        };
        allowed = true;
      }
    ];
    secondaryAlbumTypes = [
      {
        albumType = {
          id = 0;
          name = "Studio";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 3;
          name = "Spokenword";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 2;
          name = "Soundtrack";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 7;
          name = "Remix";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 9;
          name = "Mixtape/Street";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 6;
          name = "Live";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 4;
          name = "Interview";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 8;
          name = "DJ-mix";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 10;
          name = "Demo";
        };
        allowed = false;
      }
      {
        albumType = {
          id = 1;
          name = "Compilation";
        };
        allowed = true;
      }
      {
        albumType = {
          id = 11;
          name = "Audio drama";
        };
        allowed = false;
      }
    ];
    releaseStatuses = [
      {
        releaseStatus = {
          id = 3;
          name = "Pseudo-Release";
        };
        allowed = false;
      }
      {
        releaseStatus = {
          id = 1;
          name = "Promotion";
        };
        allowed = false;
      }
      {
        releaseStatus = {
          id = 0;
          name = "Official";
        };
        allowed = true;
      }
      {
        releaseStatus = {
          id = 2;
          name = "Bootleg";
        };
        allowed = false;
      }
    ];
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
        type = types.listOf types.attrs;
        description = ''
          Album types allowed as an artist's primary album types (e.g. Album, EP, Single).
          Each entry is `{ albumType = { id; name; }; allowed; }`.
        '';
      };
      secondaryAlbumTypes = mkOption {
        type = types.listOf types.attrs;
        description = ''
          Album types allowed as secondary types (e.g. Live, Compilation, Remix).
          Each entry is `{ albumType = { id; name; }; allowed; }`.
        '';
      };
      releaseStatuses = mkOption {
        type = types.listOf types.attrs;
        description = ''
          Release statuses allowed when selecting releases (e.g. Official, Promotion).
          Each entry is `{ releaseStatus = { id; name; }; allowed; }`.
        '';
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
    defaultText = literalExpression ''[ <built-in "Standard" metadata profile> ]'';
    description = ''
      List of metadata profiles to configure via the API /metadataprofile endpoint.
      Each profile is matched and reconciled by `name` (Lidarr assigns `id` per-instance).

      Defaults to a single "Standard" profile. At least one metadata profile must be present
      (enforced via assertion) — Lidarr requires one to assign to root folders and artists.
      Profiles not declared here (by name) are deleted.
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
              profileJson = builtins.toJSON profileConfig;
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
