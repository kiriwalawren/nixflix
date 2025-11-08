{lib, ...}:
with lib; let
  inherit (lib) types;
  instanceType = types.submodule {
    options = {
      base_url = mkOption {
        type = types.str;
        description = "Base URL for the service instance (including port and URL base)";
        example = "http://127.0.0.1:8989";
      };

      api_key = mkOption {
        type = types.oneOf [
          types.str
          (types.submodule {
            options._secret = mkOption {
              type = types.str;
              description = "Path to a file containing the secret value";
            };
          })
        ];
        description = ''
          API key for the service.
          Can be a plain string or a secret reference using { _secret = "/path/to/file"; }
        '';
        example = literalExpression ''{ _secret = "/run/credentials/recyclarr.service/sonarr-api_key"; }'';
      };

      delete_old_custom_formats = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to delete custom formats in the service that are not defined in the configuration";
      };

      replace_existing_custom_formats = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to replace existing custom formats with configuration from Recyclarr";
      };

      quality_definition = mkOption {
        type = types.nullOr (types.submodule {
          options.type = mkOption {
            type = types.enum ["series" "movie" "anime"];
            description = "Type of quality definition to use from TRaSH guides";
          };
        });
        default = null;
        description = "Quality definition configuration from TRaSH guides";
      };

      media_naming = mkOption {
        type = types.nullOr (
          types.either
          # Sonarr media naming
          (types.submodule {
            options = {
              series = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Series folder naming format ('default' for TRaSH guide default)";
              };

              season = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Season folder naming format ('default' for TRaSH guide default)";
              };

              episodes = mkOption {
                type = types.nullOr (types.submodule {
                  options = {
                    rename = mkOption {
                      type = types.bool;
                      default = true;
                      description = "Whether to rename episode files";
                    };

                    standard = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Standard episode naming format ('default' for TRaSH guide default)";
                    };

                    daily = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Daily episode naming format ('default' for TRaSH guide default)";
                    };

                    anime = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Anime episode naming format ('default' for TRaSH guide default)";
                    };
                  };
                });
                default = null;
                description = "Episode file naming configuration";
              };
            };
          })
          # Radarr media naming
          (types.submodule {
            options = {
              folder = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Movie folder naming format ('default' for TRaSH guide default)";
              };

              movie = mkOption {
                type = types.nullOr (types.submodule {
                  options = {
                    rename = mkOption {
                      type = types.bool;
                      default = true;
                      description = "Whether to rename movie files";
                    };

                    standard = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Movie file naming format ('default' or 'standard' for TRaSH guide defaults)";
                    };
                  };
                });
                default = null;
                description = "Movie file naming configuration";
              };
            };
          })
        );
        default = null;
        description = ''
          Media naming configuration.
          For Sonarr: configures series, season, and episode naming.
          For Radarr: configures folder and movie naming.
          Use 'default' or 'standard' to apply TRaSH guide recommendations.
        '';
      };

      quality_profiles = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Name of the quality profile";
              example = "WEB-2160p";
            };

            reset_unmatched_scores = mkOption {
              type = types.nullOr (types.submodule {
                options.enabled = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Whether to reset scores for custom formats not in the configuration";
                };
              });
              default = null;
              description = "Configuration for resetting unmatched custom format scores";
            };

            upgrade = mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  allowed = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Whether upgrades are allowed";
                  };

                  until_quality = mkOption {
                    type = types.str;
                    description = "Upgrade until this quality level is reached";
                    example = "WEB 2160p";
                  };

                  until_score = mkOption {
                    type = types.int;
                    default = 10000;
                    description = "Upgrade until this custom format score is reached";
                  };
                };
              });
              default = null;
              description = "Upgrade configuration for the quality profile";
            };

            min_format_score = mkOption {
              type = types.int;
              default = 0;
              description = "Minimum custom format score required";
            };

            quality_sort = mkOption {
              type = types.enum ["top" "bottom"];
              default = "top";
              description = "Quality sort order (top = highest quality first)";
            };

            qualities = mkOption {
              type = types.listOf (types.submodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Quality name (e.g., 'WEB 2160p', 'Bluray-1080p')";
                  };

                  qualities = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Optional list of specific quality variants (e.g., ['WEBDL-2160p', 'WEBRip-2160p'])";
                  };
                };
              });
              default = [];
              description = "Ordered list of qualities in the profile (from highest to lowest priority)";
            };
          };
        });
        default = [];
        description = "List of quality profiles to create or update";
      };

      custom_formats = mkOption {
        type = types.listOf (types.submodule {
          options = {
            trash_ids = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "List of TRaSH custom format IDs (GUIDs)";
              example = ["85c61753df5da1fb2aab6f2a47426b09"];
            };

            assign_scores_to = mkOption {
              type = types.listOf (types.submodule {
                options.name = mkOption {
                  type = types.str;
                  description = "Name of the quality profile to assign scores to";
                };
              });
              default = [];
              description = "Quality profiles to assign these custom format scores to";
            };
          };
        });
        default = [];
        description = "List of custom format configurations from TRaSH guides";
      };

      include = mkOption {
        type = types.listOf (types.submodule {
          options.template = mkOption {
            type = types.str;
            description = "Name of the TRaSH template to include";
            example = "sonarr-v4-quality-profile-web-2160p-alternative";
          };
        });
        default = [];
        description = "List of TRaSH guide templates to include";
      };
    };
  };
in
  mkOption {
    type = types.nullOr (
      types.submodule {
        options = {
          sonarr = mkOption {
            type = types.nullOr (types.attrsOf instanceType);
            default = null;
            description = "Sonarr instance configurations";
          };

          radarr = mkOption {
            type = types.nullOr (types.attrsOf instanceType);
            default = null;
            description = "Radarr instance configurations";
          };
        };
      }
    );
    default = null;
    defaultText = literalExpression "Generated from nixflix.recyclarr.sonarr and nixflix.recyclarr.radarr settings";
    example = literalExpression ''
      {
        sonarr.sonarr_main = {
          base_url = "http://127.0.0.1:8989";
          api_key._secret = "/run/credentials/recyclarr.service/sonarr-api_key";
          quality_definition.type = "series";
          quality_profiles = [{
            name = "WEB-2160p";
            upgrade = {
              allowed = true;
              until_quality = "WEB 2160p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              { name = "WEB 2160p"; qualities = ["WEBDL-2160p" "WEBRip-2160p"]; }
              { name = "WEB 1080p"; qualities = ["WEBDL-1080p" "WEBRip-1080p"]; }
            ];
          }];
          custom_formats = [{
            trash_ids = [
              "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
              "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
            ];
            assign_scores_to = [{ name = "WEB-2160p"; }];
          }];
          include = [
            { template = "sonarr-v4-quality-profile-web-2160p-alternative"; }
          ];
        };
        radarr.radarr_main = {
          base_url = "http://127.0.0.1:7878";
          api_key._secret = "/run/credentials/recyclarr.service/radarr-api_key";
          quality_definition.type = "movie";
        };
      }
    '';
    description = ''
      Recyclarr configuration as a structured Nix attribute set.
      When set, this completely replaces the auto-generated configuration,
      giving you full control over the Recyclarr setup.

      The structure is: { service_type.instance_name = { ... }; }
      - service_type: "sonarr" or "radarr" (only these two keys are allowed)
      - instance_name: arbitrary name for the instance (e.g., "sonarr_main", "radarr_4k")

      Each instance supports quality profiles, custom formats from TRaSH guides,
      media naming configuration, and template includes.

      https://recyclarr.dev/wiki/yaml/config-reference/
    '';
  }
