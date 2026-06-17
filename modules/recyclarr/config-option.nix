{ lib, ... }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };

  radarrMediaNamingType = types.submodule {
    options = {
      folder = mkOption {
        type = types.nullOr types.str;
        default = "jellyfin-tmdb";
        description = ''
          A naming format taken from the 'Key' column of the 'Movie Folder Format' table.

          Can be acquired from `nix run nixpkgs#recyclarr -- list naming radarr`.
        '';
      };

      movie = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              rename = mkOption {
                type = types.bool;
                default = true;
                description = "Enables the 'Rename Movies' checkbox when set to `true`.";
              };

              standard = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "A naming format taken from the 'Key' column of the 'Standard Movie Format' table.";
              };
            };
          }
        );
        default = null;
        description = "Movie file naming configuration.";
      };
    };
  };

  sonarrMediaNamingType = types.submodule {
    options = {
      series = mkOption {
        type = types.nullOr types.str;
        default = "jellyfin-tvdb";
        description = ''
          A naming format taken from the 'Key' column of the 'Series Folder Format' table.

          Can be acquired from `nix run nixpkgs#recyclarr -- list naming sonarr`.
        '';
      };

      season = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "A naming format taken from the 'Key' column of the 'Season Folder Format' table.";
      };

      episodes = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              rename = mkOption {
                type = types.bool;
                default = true;
                description = "Enables the 'Rename Episodes' checkbox when set to `true`.";
              };

              standard = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Standard episode naming format key.";
              };

              daily = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Daily episode naming format key.";
              };

              anime = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Anime episode naming format key.";
              };
            };
          }
        );
        default = null;
        description = "Episode file naming configuration.";
      };
    };
  };

  mkInstanceType =
    instanceType:
    types.submodule {
      options = {
        base_url = mkOption {
          type = types.str;
          description = "The base URL of your instance. Basically this is the URL you bookmark to get to the front page.";
          example = "http://127.0.0.1:8989";
        };

        api_key = secrets.mkSecretOption {
          description = "The API key that Recyclarr should use to synchronize settings to your instance.";
        };

        delete_old_custom_formats = mkOption {
          type = types.bool;
          default = false;
          description = ''
            If enabled, custom formats that you remove from your configuration or that are
            removed from the guide will be deleted from the service. Only applies to formats
            Recyclarr synchronized; manually added formats are preserved.
          '';
        };

        quality_definition = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                type = mkOption {
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
                  description = "Identifies which quality size settings to parse and upload.";
                };

                preferred_ratio = mkOption {
                  type = types.nullOr (types.numbers.between 0.0 1.0);
                  default = null;
                  description = ''
                    A value 0.0 to 1.0 that represents the percentage (interpolated) position
                    of the preferred quality slider between minimum and maximum. Values outside
                    the range are clamped with a warning. Has no effect on Sonarr v3.
                  '';
                };

                qualities = mkOption {
                  type = types.nullOr (
                    types.listOf (
                      types.submodule {
                        options = {
                          name = mkOption {
                            type = types.str;
                            description = "The name of a quality to override. Must exist in the guide (case-insensitive).";
                            example = "Bluray-1080p";
                          };

                          min = mkOption {
                            type = types.nullOr types.numbers.nonnegative;
                            default = null;
                            description = "Minimum size in MB per minute of runtime.";
                          };

                          max = mkOption {
                            type = types.nullOr (types.either types.numbers.nonnegative (types.enum [ "unlimited" ]));
                            default = null;
                            description = ''
                              Maximum size in MB per minute of runtime, or `"unlimited"`.
                            '';
                          };

                          preferred = mkOption {
                            type = types.nullOr (types.either types.numbers.nonnegative (types.enum [ "unlimited" ]));
                            default = null;
                            description = ''
                              Preferred size in MB per minute of runtime, or `"unlimited"`.
                            '';
                          };
                        };
                      }
                    )
                  );
                  default = null;
                  description = ''
                    Override size limits for specific qualities while retaining guide defaults
                    for others. Constraint: min ≤ preferred ≤ max.
                  '';
                };
              };
            }
          );
          default = null;
          description = "Control the minimum, maximum, and preferred file sizes for each quality level.";
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
                  Controls how Sonarr/Radarr handles Propers and Repacks. This corresponds
                  to the 'Propers and Repacks' dropdown in the Media Management settings.
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
                  description = "The trash ID of a TRaSH Guide quality profile definition.";
                  example = "0896c29d74de619df168d23b98104b22";
                };

                name = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    The name of the quality profile. For guide-backed profiles (with
                    `trash_id`), this defaults to the guide's recommended name and may be
                    overridden. For user-defined profiles, this is the profile identity.
                    Either `trash_id` or `name` is required.
                  '';
                  example = "WEB-2160p";
                };

                score_set = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "A string (name) that determines the guide-provided, preset scores to use across all custom formats assigned to a quality profile.";
                };

                reset_unmatched_scores = mkOption {
                  type = types.nullOr (
                    types.submodule {
                      options = {
                        enabled = mkOption {
                          type = types.bool;
                          default = true;
                          description = "If `true`, custom format scores not managed by Recyclarr are set to `0`. If `false`, scores are only altered when listed in `trash_ids` with a valid score.";
                        };

                        except = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "A list of one or more custom format names to exclude from score resets. Names must match exactly (case-sensitive).";
                        };

                        except_patterns = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "A list of one or more regular expression patterns used to exclude custom formats from score resets. Matching is case-insensitive.";
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
                          description = "Directly correlates to the 'Upgrades Allowed' checkbox in the Quality Profile edit dialog in Radarr/Sonarr.";
                        };

                        until_quality = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "The quality name mentioned here must exist in the `qualities` list or be a valid quality in your profile.";
                          example = "WEB 2160p";
                        };

                        until_score = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                          description = "Correlates directly to the 'Upgrade Until Custom Format Score' field in the Quality Profile edit dialog.";
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
                  description = "Correlates directly to the 'Minimum Custom Format Score' field in the Quality Profile edit dialog in Radarr/Sonarr.";
                };

                min_upgrade_format_score = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  description = "Correlates directly to the 'Minimum Custom Format Score For Upgrades' field in the Quality Profile edit dialog in Radarr/Sonarr.";
                };

                quality_sort = mkOption {
                  type = types.nullOr (
                    types.enum [
                      "top"
                      "bottom"
                    ]
                  );
                  default = null;
                  description = "Controls which direction specified qualities are sorted. `top` sorts them to the top of the list; `bottom` sorts them to the bottom.";
                };

                qualities = mkOption {
                  type = types.nullOr (
                    types.listOf (
                      types.submodule {
                        options = {
                          name = mkOption {
                            type = types.str;
                            description = "The name of an existing quality. If this is a quality group, this name identifies either an existing quality group or will be used as the name for a newly created group.";
                            example = "WEB 2160p";
                          };

                          enabled = mkOption {
                            type = types.bool;
                            default = true;
                            description = "If `true`, this quality will be allowed. If `false`, this quality will be disallowed.";
                          };

                          qualities = mkOption {
                            type = types.nullOr (types.listOf types.str);
                            default = null;
                            description = "A list of one or more existing qualities to bundle into a group. By specifying this list, you implicitly make this item a quality group.";
                            example = [
                              "WEBDL-2160p"
                              "WEBRip-2160p"
                            ];
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
            An array of quality profiles that Recyclarr should create or modify.

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
                  description = "Trash IDs of the custom formats to synchronize.";
                  example = [ "85c61753df5da1fb2aab6f2a47426b09" ];
                };

                assign_scores_to = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        trash_id = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "The trash ID of a guide-backed quality profile. Remains stable across guide updates.";
                        };
                        name = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "The name of the quality profile. Works for both guide-backed and user-defined profiles.";
                        };
                        score = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                          description = "Score override applied to all custom formats in this list. Omit to use guide default scores.";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Quality profiles to receive scores from these custom formats.";
                };
              };
            }
          );
          default = [ ];
          description = "Sets of custom formats with optional quality profile assignments for score application.";
        };

        custom_format_groups = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                skip = mkOption {
                  type = types.nullOr (types.listOf types.str);
                  default = null;
                  description = "Trash IDs of groups to exclude from auto-sync.";
                };

                add = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        trash_id = mkOption {
                          type = types.str;
                          description = "The trash ID of the custom format group.";
                        };

                        assign_scores_to = mkOption {
                          type = types.nullOr (
                            types.listOf (
                              types.submodule {
                                options = {
                                  trash_id = mkOption {
                                    type = types.nullOr types.str;
                                    default = null;
                                    description = "The trash ID of a guide-backed quality profile.";
                                  };
                                  name = mkOption {
                                    type = types.nullOr types.str;
                                    default = null;
                                    description = "The name of the quality profile.";
                                  };
                                };
                              }
                            )
                          );
                          default = null;
                          description = "Quality profiles to receive scores from this group. If omitted, scores are assigned to all applicable guide-backed profiles.";
                        };

                        select_all = mkOption {
                          type = types.nullOr types.bool;
                          default = null;
                          description = "When `true`, all non-required custom formats in the group are included. Mutually exclusive with `select`.";
                        };

                        select = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "Non-default custom formats to include alongside defaults. Mutually exclusive with `select_all`.";
                        };

                        exclude = mkOption {
                          type = types.nullOr (types.listOf types.str);
                          default = null;
                          description = "Trash IDs of custom formats to remove from the synced set. Required CFs cannot be excluded.";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Groups to explicitly synchronize. Use this to customize default group behavior or opt in to non-default groups.";
                };
              };
            }
          );
          default = null;
          description = ''
            Controls which custom format groups synchronize from the TRaSH Guides. Groups
            marked `default: true` in the guide are automatically synced when using
            guide-backed quality profiles. Use `skip` to opt out of defaults or `add` to
            opt in to non-default groups.
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
                    The ID of an include template from a resource provider. As of Recyclarr
                    v8 the official repository no longer ships any include templates, so this
                    only works with a custom resource provider or user-supplied local includes.
                  '';
                };

                config = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    An absolute or relative path to the YAML file to include. Relative paths
                    resolve from the `includes` directory in the Recyclarr app data folder.
                  '';
                };
              };
            }
          );
          default = [ ];
          description = ''
            A sequence of include directives to merge into this instance. Each entry must
            set exactly one of `template` or `config`.
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

      [Config Reference](https://recyclarr.dev/reference/configuration/)
    '';
  };
}
