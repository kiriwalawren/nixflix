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

  defaultQualityProfile = {
    name = "Any";
    upgradeAllowed = true;
    cutoff = 1005;
    items = [
      {
        quality = {
          id = 0;
          name = "Unknown";
        };
        items = [ ];
        allowed = true;
      }
      {
        name = "Trash Quality Lossy";
        items = [
          {
            quality = {
              id = 32;
              name = "MP3-8";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 31;
              name = "MP3-16";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 30;
              name = "MP3-24";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 29;
              name = "MP3-32";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 28;
              name = "MP3-40";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 27;
              name = "MP3-48";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 26;
              name = "MP3-56";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 25;
              name = "MP3-64";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 24;
              name = "MP3-80";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1000;
      }
      {
        name = "Poor Quality Lossy";
        items = [
          {
            quality = {
              id = 23;
              name = "MP3-96";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 33;
              name = "MP3-112";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 22;
              name = "MP3-128";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 19;
              name = "OGG Vorbis Q5";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 5;
              name = "MP3-160";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1001;
      }
      {
        name = "Low Quality Lossy";
        items = [
          {
            quality = {
              id = 1;
              name = "MP3-192";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 18;
              name = "OGG Vorbis Q6";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 9;
              name = "AAC-192";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 20;
              name = "WMA";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 34;
              name = "MP3-224";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1002;
      }
      {
        name = "Mid Quality Lossy";
        items = [
          {
            quality = {
              id = 17;
              name = "OGG Vorbis Q7";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 8;
              name = "MP3-VBR-V2";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 3;
              name = "MP3-256";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 16;
              name = "OGG Vorbis Q8";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 10;
              name = "AAC-256";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1003;
      }
      {
        name = "High Quality Lossy";
        items = [
          {
            quality = {
              id = 2;
              name = "MP3-VBR-V0";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 12;
              name = "AAC-VBR";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 4;
              name = "MP3-320";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 15;
              name = "OGG Vorbis Q9";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 11;
              name = "AAC-320";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 14;
              name = "OGG Vorbis Q10";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1004;
      }
      {
        name = "Lossless";
        items = [
          {
            quality = {
              id = 6;
              name = "FLAC";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 7;
              name = "ALAC";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 35;
              name = "APE";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 36;
              name = "WavPack";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 21;
              name = "FLAC 24bit";
            };
            items = [ ];
            allowed = true;
          }
          {
            quality = {
              id = 37;
              name = "ALAC 24bit";
            };
            items = [ ];
            allowed = true;
          }
        ];
        allowed = true;
        id = 1005;
      }
      {
        quality = {
          id = 13;
          name = "WAV";
        };
        items = [ ];
        allowed = false;
      }
    ];
    minFormatScore = 0;
    cutoffFormatScore = 0;
    formatItems = [ ];
    id = 1;
  };

  qualityProfileType = types.submodule {
    freeformType = types.attrsOf types.anything;
    options = {
      name = mkOption {
        type = types.str;
        description = "Name of the quality profile, shown in the Lidarr UI. Used to match against existing profiles.";
      };
      upgradeAllowed = mkOption {
        type = types.bool;
        description = "Whether Lidarr is allowed to upgrade an album to a better quality once the initial quality requirement is met.";
      };
      cutoff = mkOption {
        type = types.int;
        description = ''
          The quality/group `id` at which Lidarr stops upgrading (only relevant when `upgradeAllowed = true`).
          Must match one of the `id`s (or a `quality.id`) present in `items`.
        '';
      };
      items = mkOption {
        type = types.listOf types.attrs;
        description = ''
          Ordered list of qualities/quality groups this profile allows, from lowest to highest priority.
          Each entry is either a single quality (`{ quality = { id; name; }; items = []; allowed; }`)
          or a named group of qualities (`{ name; id; items = [ <quality items> ]; allowed; }`).
        '';
      };
      minFormatScore = mkOption {
        type = types.int;
        default = 0;
        description = "Minimum custom format score a release must meet to be grabbed.";
      };
      cutoffFormatScore = mkOption {
        type = types.int;
        default = 0;
        description = "Custom format score at which Lidarr stops upgrading for format score alone.";
      };
      formatItems = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "Custom format scoring overrides for this profile (see Recyclarr for managed custom formats).";
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
  options.nixflix.lidarr.config.qualityProfiles = mkOption {
    type = types.listOf qualityProfileType;
    default = [ ];
    description = ''
      List of quality profiles to configure via the API /qualityprofile endpoint.
      Each profile is matched and reconciled by `name` (Lidarr assigns `id` per-instance).

      A default "Any" profile is always included unless overridden by declaring
      your own profile named "Any". Profiles not declared here (by name) are deleted.
    '';
  };

  config.systemd.services."lidarr-qualityprofiles" =
    mkIf (config.nixflix.enable && cfg.enable && cfg.config.apiKey != null)
      (
        let
          userNames = map (p: p.name) cfg.config.qualityProfiles;
          mergedProfiles =
            cfg.config.qualityProfiles
            ++ optional (!(elem defaultQualityProfile.name userNames)) defaultQualityProfile;
        in
        {
          description = "Configure Lidarr quality profiles via API";
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

            echo "Fetching existing quality profiles..."
            QUALITY_PROFILES=$(${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/qualityprofile";
                extraArgs = "-Sf";
              }
            } 2>/dev/null)

            CONFIGURED_NAMES=$(cat <<'EOF'
            ${builtins.toJSON (map (p: p.name) mergedProfiles)}
            EOF
            )

            echo "Removing quality profiles not in configuration..."
            echo "$QUALITY_PROFILES" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r profile; do
              PROFILE_NAME=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.name')
              PROFILE_ID=$(echo "$profile" | ${pkgs.jq}/bin/jq -r '.id')

              if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$PROFILE_NAME" 'index($name)' >/dev/null 2>&1; then
                echo "Deleting quality profile not in config: $PROFILE_NAME (ID: $PROFILE_ID)"
                ${
                  mkSecureCurl cfg.config.apiKey {
                    url = "$BASE_URL/qualityprofile/$PROFILE_ID";
                    method = "DELETE";
                    extraArgs = "-Sf";
                  }
                } >/dev/null 2>&1 || echo "Warning: Failed to delete quality profile $PROFILE_NAME (may be in use)"
              fi
            done

            ${concatMapStringsSep "\n" (
              profileConfig:
              let
                profileJson = builtins.toJSON profileConfig;
                profileName = profileConfig.name;
              in
              ''
                echo "Processing quality profile: ${profileName}"

                EXISTING_PROFILE=$(echo "$QUALITY_PROFILES" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg profileName} '.[] | select(.name == $name) | @json' || echo "")

                if [ -n "$EXISTING_PROFILE" ]; then
                  EXISTING_ID=$(echo "$EXISTING_PROFILE" | ${pkgs.jq}/bin/jq -r '.id')
                  echo "Quality profile ${profileName} already exists (ID: $EXISTING_ID), updating..."
                  UPDATED_PROFILE=$(echo ${escapeShellArg profileJson} | ${pkgs.jq}/bin/jq --argjson id "$EXISTING_ID" '.id = $id')
                  ${
                    mkSecureCurl cfg.config.apiKey {
                      url = "$BASE_URL/qualityprofile/$EXISTING_ID";
                      method = "PUT";
                      headers = {
                        "Content-Type" = "application/json";
                      };
                      data = "$UPDATED_PROFILE";
                      extraArgs = "-Sf";
                    }
                  } > /dev/null
                  echo "Quality profile ${profileName} updated"
                else
                  echo "Quality profile ${profileName} does not exist, creating..."
                  NEW_PROFILE=$(echo ${escapeShellArg profileJson} | ${pkgs.jq}/bin/jq 'del(.id)')
                  ${
                    mkSecureCurl cfg.config.apiKey {
                      url = "$BASE_URL/qualityprofile";
                      method = "POST";
                      headers = {
                        "Content-Type" = "application/json";
                      };
                      data = "$NEW_PROFILE";
                      extraArgs = "-Sf";
                    }
                  } > /dev/null
                  echo "Quality profile ${profileName} created"
                fi
              ''
            ) mergedProfiles}

            echo "Lidarr quality profiles configuration complete"
          '';
        }
      );
}
