{ lib, ... }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };

  radarrMediaNamingType = types.submodule {
    options = {
      folder = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Movie folder naming format ('default' for TRaSH guide default)";
      };

      movie = mkOption {
        type = types.nullOr (
          types.submodule {
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
          }
        );
        default = null;
        description = "Movie file naming configuration";
      };
    };
  };

  sonarrMediaNamingType = types.submodule {
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
        type = types.nullOr (
          types.submodule {
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
          }
        );
        default = null;
        description = "Episode file naming configuration";
      };
    };
  };

  mkInstanceType =
    instanceType:
    types.submodule {
      options = {
        base_url = mkOption {
          type = types.str;
          description = "Base URL for the service instance (including port and URL base).";
          example = "http://127.0.0.1:8989";
        };

        api_key = secrets.mkSecretOption {
          description = "API key for the instance.";
        };

        delete_old_custom_formats = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to delete custom formats in the service that are not defined in the configuration.";
        };

        quality_definition = mkOption {
          type = types.nullOr (
            types.submodule {
              options.type = mkOption {
                type = types.enum (
                  if instanceType == "radarr" then
                    [
                      "movie"
                      "anime"
                      "sqp-streaming"
                      "sqp-uhd"
                    ]
                  else
                    [
                      "series"
                      "anime"
                    ]
                );
                description = "Type of quality definition to use from TRaSH guides.";
              };
            }
          );
          default = null;
          description = "Quality definition configuration from TRaSH guides.";
        };

        media_management = mkOption {
          type = types.nullOr (
            types.submodule {
              options.propers_and_repacks = mkOption {
                type = types.nullOr (
                  types.enum [
                    "prefer_and_upgrade"
                    "do_not_upgrade"
                    "do_not_prefer"
                  ]
                );
                default = null;
                description = ''
                  How to handle Propers and Repacks. Set to `do_not_prefer` when using
                  Custom Formats for repack/proper handling.
                '';
              };
            }
          );
          default = null;
          description = "Media management settings.";
        };

        media_naming = mkOption {
          type = types.nullOr (
            if instanceType == "radarr" then radarrMediaNamingType else sonarrMediaNamingType
          );
          default = null;
          description = ''
            Media naming configuration.

            Use 'default' or 'standard' to apply TRaSH guide recommendations.
          '';
        };

        quality_profiles = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                trash_id = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    The trash_id of a guide-backed quality profile. When specified, qualities,
                    custom formats, scores, and language are automatically configured from the
                    TRaSH Guides.
                  '';
                  example = "0896c29d74de619df168d23b98104b22";
                };

                name = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Name of the quality profile. For guide-backed profiles (with `trash_id`),
                    this overrides the guide name. For user-defined profiles, this is the
                    profile identity. Either `trash_id` or `name` is required.
                  '';
                  example = "WEB-2160p";
                };

                score_set = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "The set of scores to use for custom formats assigned to the profile.";
                };

                reset_unmatched_scores = mkOption {
                  type = types.nullOr (
                    types.submodule {
                      options = {
                        enabled = mkOption {
                          type = types.bool;
                          default = true;
                          description = "Whether to reset scores for custom formats not in the configuration.";
                        };

                        except = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "Custom format names to exclude when resetting scores (case-insensitive).";
                        };

                        except_patterns = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "Regular expression patterns to exclude when resetting scores (case-insensitive).";
                        };
                      };
                    }
                  );
                  default = null;
                  description = "Configuration for resetting unmatched custom format scores.";
                };

                upgrade = mkOption {
                  type = types.nullOr (
                    types.submodule {
                      options = {
                        allowed = mkOption {
                          type = types.bool;
                          default = true;
                          description = "Whether upgrades are allowed.";
                        };

                        until_quality = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Upgrade until this quality level is reached.";
                          example = "WEB 2160p";
                        };

                        until_score = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                          description = "Upgrade until this custom format score is reached.";
                        };
                      };
                    }
                  );
                  default = null;
                  description = "Upgrade configuration for the quality profile.";
                };

                min_format_score = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  description = "Minimum custom format score required to download a release.";
                };

                min_upgrade_format_score = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  description = ''
                    Minimum custom format score required to upgrade an already-downloaded
                    release.
                  '';
                };

                quality_sort = mkOption {
                  type = types.nullOr (
                    types.enum [
                      "top"
                      "bottom"
                    ]
                  );
                  default = null;
                  description = "Quality sort order (top = highest quality first).";
                };

                qualities = mkOption {
                  type = types.nullOr (
                    types.listOf (
                      types.submodule {
                        options = {
                          name = mkOption {
                            type = types.str;
                            description = "Quality name (e.g., 'WEB 2160p', 'Bluray-1080p').";
                          };

                          enabled = mkOption {
                            type = types.bool;
                            default = true;
                            description = "Whether this quality is enabled in the profile.";
                          };

                          qualities = mkOption {
                            type = types.nullOr (types.listOf types.str);
                            default = null;
                            description = "Optional list of specific quality variants (e.g., `['WEBDL-2160p', 'WEBRip-2160p']`).";
                          };
                        };
                      }
                    )
                  );
                  default = null;
                  description = "Ordered list of qualities in the profile (from highest to lowest priority).";
                };
              };
            }
          );
          default = [ ];
          description = ''
            List of quality profiles to create or update.

            Prefer setting `trash_id` to use a guide-backed profile — qualities, custom
            formats, scores, and language will be configured automatically from the
            TRaSH Guides. For user-defined profiles, set `name` along with `qualities`
            and other fields.
          '';
        };

        custom_formats = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                trash_ids = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "List of TRaSH custom format IDs (GUIDs)";
                  example = [ "85c61753df5da1fb2aab6f2a47426b09" ];
                };

                assign_scores_to = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        trash_id = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = ''
                            Guide-backed quality profile trash_id to assign scores to.
                            Either `trash_id` or `name` must be specified.
                          '';
                        };
                        name = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = ''
                            Name of the quality profile to assign scores to.
                            Either `trash_id` or `name` must be specified.
                          '';
                        };
                        score = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                          description = "Optional score override; omit to use the TRaSH guide default score";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Quality profiles to assign these custom format scores to";
                };
              };
            }
          );
          default = [ ];
          description = "List of custom format configurations from TRaSH guides";
        };

        custom_format_groups = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                skip = mkOption {
                  type = types.nullOr (types.listOf types.str);
                  default = null;
                  description = ''
                    Trash IDs of custom format groups to skip. Use this to opt out of
                    auto-synced default groups.
                  '';
                };

                add = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        trash_id = mkOption {
                          type = types.str;
                          description = "Trash ID of the custom format group to add.";
                        };

                        assign_scores_to = mkOption {
                          type = types.nullOr (
                            types.listOf (
                              types.submodule {
                                options = {
                                  trash_id = mkOption {
                                    type = types.nullOr types.str;
                                    default = null;
                                    description = "Guide-backed quality profile trash_id to assign scores to.";
                                  };
                                  name = mkOption {
                                    type = types.nullOr types.str;
                                    default = null;
                                    description = "Name of the quality profile to assign scores to.";
                                  };
                                };
                              }
                            )
                          );
                          default = null;
                          description = ''
                            Quality profiles to assign scores to. If omitted, scores are
                            assigned to all guide-backed profiles.
                          '';
                        };

                        select_all = mkOption {
                          type = types.nullOr types.bool;
                          default = null;
                          description = ''
                            Include all custom formats in the group regardless of their
                            default status. Mutually exclusive with `select`.
                          '';
                        };

                        select = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = ''
                            Non-default custom formats to additionally include. Required CFs
                            are always included. Mutually exclusive with `select_all`.
                          '';
                        };

                        exclude = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = ''
                            Default custom formats to exclude from the group. Required CFs
                            cannot be excluded.
                          '';
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = ''
                    Custom format groups to explicitly add. Use this for non-default groups
                    or groups not auto-matched to your profiles.
                  '';
                };
              };
            }
          );
          default = null;
          description = ''
            Custom format groups from the TRaSH Guides. Groups marked `default: true` in
            the guide are automatically synced when using guide-backed quality profiles.
            Use `skip` to opt out of defaults or `add` to opt in to non-default groups.
          '';
        };

        include = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                template = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    ID of a config include template from the Recyclarr
                    [config-templates repository](https://github.com/recyclarr/config-templates)
                    (or a local replacement). As of Recyclarr v8 the official repository no
                    longer ships any include templates, so this only works with a custom
                    resource provider or user-supplied local includes.
                  '';
                };

                config = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Path to a local YAML file (relative paths are resolved under the
                    Recyclarr `includes` directory) to merge into this instance's config.
                  '';
                };
              };
            }
          );
          default = [ ];
          description = ''
            List of includes to merge into this instance. Each entry must set exactly one
            of `template` or `config`.
          '';
        };
      };
    };
in
{
  options.nixflix.recyclarr.config = mkOption {
    type = types.nullOr (
      types.submodule {
        options = {
          sonarr = mkOption {
            type = types.nullOr (types.attrsOf (mkInstanceType "sonarr"));
            default = null;
            description = "Sonarr instance configurations";
          };

          radarr = mkOption {
            type = types.nullOr (types.attrsOf (mkInstanceType "radarr"));
            default = null;
            description = "Radarr instance configurations";
          };
        };
      }
    );
    default = null;
    defaultText = "Generated from `nixflix.sonarr`, `nixflix.sonarr-anime`, and `nixflix.radarr` settings";
    example = literalExpression ''
      {
        sonarr.sonarr_main = {
          base_url = "http://127.0.0.1:8989";
          api_key._secret = "/run/credentials/recyclarr.service/sonarr-api_key";
          quality_definition.type = "series";
          quality_profiles = [{
            trash_id = "dfa5eaae7894077ad6449169b6eb03e0"; # WEB-2160p (Alternative)
            reset_unmatched_scores.enabled = true;
          }];
          custom_format_groups.add = [{
            trash_id = "e3f37512790f00d0e89e54fe5e790d1c"; # [Required] Golden Rule UHD
            select = [ "9b64dff695c2115facf1b6ea59c9bd07" ]; # x265 (no HDR/DV)
          }];
        };
        radarr.radarr_main = {
          base_url = "http://127.0.0.1:7878";
          api_key._secret = "/run/credentials/recyclarr.service/radarr-api_key";
          quality_definition.type = "movie";
          media_management.propers_and_repacks = "do_not_prefer";
        };
      }
    '';
    description = ''
      Recyclarr configuration as a structured Nix attribute set.
      When set, this completely replaces the auto-generated configuration,
      giving you full control over the Recyclarr setup.

      The structure is: `{ service_type.instance_name = { ... }; }`

      - service_type: `sonarr` or `radarr` (only these two keys are allowed)
      - instance_name: arbitrary name for the instance (e.g., `sonarr_main`, `radarr_4k`)

      Defaults are `sonarr.sonarr`, `sonarr.sonarr_anime`, and `radarr.radarr`.

      Each instance supports guide-backed quality profiles (via `trash_id`) or
      user-defined ones (via `name`), custom formats and custom format groups
      from TRaSH guides, media naming, media management (e.g. Propers and
      Repacks handling), and template/file includes.

      [Config Reference](https://recyclarr.dev/wiki/yaml/config-reference/)
    '';
  };
}
