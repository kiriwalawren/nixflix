{ lib, secrets }: with lib;
rec {
  allServices = [
    "sonarr"
    "sonarr-anime"
    "radarr"
    "lidarr"
  ];

  allTriggers = {
    sonarr = [
      "onGrab"
      "onDownload"
      "onUpgrade"
      "onImportComplete"
      "onRename"
      "onSeriesAdd"
      "onSeriesDelete"
      "onEpisodeFileDelete"
      "onEpisodeFileDeleteForUpgrade"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    radarr = [
      "onGrab"
      "onDownload"
      "onUpgrade"
      "onRename"
      "onMovieAdded"
      "onMovieDelete"
      "onMovieFileDelete"
      "onMovieFileDeleteForUpgrade"
      "onHealthIssue"
      "onHealthRestored"
      "onApplicationUpdate"
      "onManualInteractionRequired"
    ];
    lidarr = [
      "onGrab"
      "onReleaseImport"
      "onUpgrade"
      "onRename"
      "onArtistAdd"
      "onArtistDelete"
      "onAlbumDelete"
      "onHealthIssue"
      "onHealthRestored"
      "onDownloadFailure"
      "onImportFailure"
      "onTrackRetag"
      "onApplicationUpdate"
    ];
  };

  # Triggers the Starr UI leaves unchecked when a connection is added
  # (SELECT_NOTIFICATION_SCHEMA in each frontend's notifications.js).
  uiDefaultOff = {
    sonarr = [
      "onHealthIssue"
      "onHealthRestored"
    ];
    radarr = [
      "onHealthIssue"
      "onHealthRestored"
    ];
    lidarr = [
      "onAlbumDelete"
      "onHealthRestored"
    ];
  };

  # Seerr notification agents (NotificationAgentKey in Seerr's server/lib/settings/index.ts).
  seerrAgents = [
    "discord"
    "email"
    "gotify"
    "ntfy"
    "pushbullet"
    "pushover"
    "slack"
    "telegram"
    "webhook"
    "webpush"
  ];

  # Seerr's Notification Types toggles (src/components/NotificationTypeSelector) and their bits.
  seerrEvents = [
    {
      name = "onMediaAutoRequested";
      label = "Request Automatically Submitted";
      bit = 4096;
    }
    {
      name = "onMediaPending";
      label = "Request Pending Approval";
      bit = 2;
    }
    {
      name = "onMediaAutoApproved";
      label = "Request Automatically Approved";
      bit = 128;
    }
    {
      name = "onMediaApproved";
      label = "Request Approved";
      bit = 4;
    }
    {
      name = "onMediaDeclined";
      label = "Request Declined";
      bit = 64;
    }
    {
      name = "onMediaAvailable";
      label = "Request Available";
      bit = 8;
    }
    {
      name = "onMediaFailed";
      label = "Request Processing Failed";
      bit = 16;
    }
    {
      name = "onIssueCreated";
      label = "Issue Reported";
      bit = 256;
    }
    {
      name = "onIssueComment";
      label = "Issue Comment";
      bit = 512;
    }
    {
      name = "onIssueResolved";
      label = "Issue Resolved";
      bit = 1024;
    }
    {
      name = "onIssueReopened";
      label = "Issue Reopened";
      bit = 2048;
    }
  ];

  resolveFor =
    serviceName: n:
    removeAttrs n (allServices ++ [ "seerr" ])
    // filterAttrs (_: v: v != null) (n.${serviceName} or { });

  # Maps { seerrKey = "nixflixName"; } to Seerr option values from a resolved connector config.
  seerrOptions = resolved: mapping: mapAttrs (_: name: resolved.${name} or null) mapping;

  seerrTypes =
    resolved: foldl' (acc: e: acc + (if resolved.${e.name} or false then e.bit else 0)) 0 seerrEvents;

  baseService = svc: if svc == "sonarr-anime" then "sonarr" else svc;

  withSonarrAnime =
    perService:
    perService
    // optionalAttrs (perService ? sonarr && !(perService ? "sonarr-anime")) {
      sonarr-anime = perService.sonarr;
    };

  field =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  secretField =
    description:
    secrets.mkSecretOption {
      inherit description;
      nullable = true;
    };

  triggerOption =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };

  mkConnectorOption =
    {
      implementationName,
      description,
      perService,
      fields ? { },
      fieldRenames ? { },
    }:
    mkOption {
      type = mkNotificationType {
        inherit implementationName;
        seerr = perService.seerr or null;
        perService = mapAttrs (
          svc: spec:
          let
            unsupported = spec.unsupportedTriggers or [ ];
            unknownKeys = subtractLists [ "unsupportedTriggers" "fields" ] (attrNames spec);
            unknownTriggers = subtractLists allTriggers.${baseService svc} unsupported;
            valid = subtractLists unsupported allTriggers.${baseService svc};
          in
          assert assertMsg (
            isAttrs spec && unknownKeys == [ ]
          ) "${implementationName}: perService.${svc} only takes unsupportedTriggers and fields";
          assert assertMsg (
            unknownTriggers == [ ]
          ) "${implementationName}: ${svc} has no triggers named ${concatStringsSep ", " unknownTriggers}";
          {
            triggers = {
              inherit valid;
              default = subtractLists uiDefaultOff.${baseService svc} valid;
            };
            fields = spec.fields or { };
          }
        ) (withSonarrAnime (removeAttrs perService [ "seerr" ]));
        extraOptions = fields;
        inherit fieldRenames;
      };
      default = { };
      inherit description;
    };

  mkNotificationType =
    {
      implementationName,
      perService,
      dependencies ? { },
      extraOptions ? { },
      imports ? [ ],
      removedOptions ? { },
      omitFields ? [ ],
      fieldRenames ? { },
      seerr ? null,
    }:
    let
      allPerService = withSonarrAnime perService;
      seerrHasTypes = seerr.hasTypes or true;
      perServiceEnable = "Set `enable = true` in the block of each service to target instead, for example `nixflix.notif.<connector>.radarr.enable = true;`.";
      allRemovedOptions = removedOptions // {
        enable = perServiceEnable;
        services = perServiceEnable;
      };
      resolve = opts: cfg: if isFunction opts then opts cfg else opts;
    in
    types.submodule (
      { config, ... }:
      let
        fieldOptions = {
          name = mkOption {
            type = types.str;
            default = implementationName;
            description = "User-defined name for the notification instance.";
          };

          includeHealthWarnings = field types.bool "Include health warnings, not only errors, in health notifications.";

          tags = mkOption {
            type = types.listOf (types.strMatching "[a-z0-9-]+");
            default = [ ];
            description = "Starr tags (by label) that restrict this connection to tagged items. Missing tags are created.";
          };
        }
        // resolve extraOptions config;

        overrideOption =
          svc: name: opt:
          removeAttrs opt [ "defaultText" ]
          // {
            type = types.nullOr opt.type;
            default = null;
            description = "Overrides `${name}` for ${svc}. Null uses the connector-level value.";
          };

        serviceBlock =
          svc: spec:
          let
            ownOptions =
              genAttrs spec.triggers.valid (
                t: triggerOption (elem t spec.triggers.default) "Whether to notify on ${t} from ${svc}."
              )
              // resolve (spec.fields or { }) config;
            overrides = mapAttrs (overrideOption svc) fieldOptions;
          in
          {
            ${svc} = mkOption {
              type = types.submodule {
                options =
                  overrides
                  // ownOptions
                  // {
                    enable = mkOption (
                      {
                        type = types.bool;
                        default = false;
                        description = "Whether to configure this notification on ${svc}.";
                      }
                      // (spec.enable or { })
                    );
                  };
              };
              default = { };
              description = "Settings and triggers for ${svc}. Any connector-level field set here overrides it for ${svc} only.";
            };
          };

        seerrBlock = optionalAttrs (seerr != null) {
          seerr = mkOption {
            type = types.submodule {
              options =
                mapAttrs (overrideOption "seerr") (
                  filterAttrs (name: _: elem name (seerr.mappedFields or [ ])) fieldOptions
                )
                // resolve (seerr.fields or { }) config
                // optionalAttrs seerrHasTypes (
                  listToAttrs (
                    map (
                      e: nameValuePair e.name (triggerOption true "Whether to notify on ${e.label} from Seerr.")
                    ) seerrEvents
                  )
                )
                // {
                  embedPoster = field types.bool "Whether to include the media poster in notifications from Seerr. Null keeps Seerr's current value.";
                  enable = mkOption (
                    {
                      type = types.bool;
                      default = false;
                      description = "Whether to configure this notification on Seerr.";
                    }
                    // (seerr.enable or { })
                  );
                };
            };
            default = { };
            description = ''
              Settings for Seerr's ${seerr.agent} agent. Fields set here override the connector-level ones for
              Seerr only. Seerr has a single ${seerr.agent} configuration, so only one connector can target it.
            '';
          };
        };
      in
      {
        inherit imports;
        options = {
          dependencies = mkOption (
            {
              type = types.listOf types.str;
              default = [ ];
              description = "systemd services that this integration depends on";
            }
            // dependencies
          );

          implementationName = mkOption {
            type = types.str;
            readOnly = true;
            default = implementationName;
            description = "Type of notification to configure (matches schema implementationName).";
          };

          _supportedTriggers = mkOption {
            type = types.attrsOf (types.listOf types.str);
            readOnly = true;
            internal = true;
            default = mapAttrs (_: spec: spec.triggers.valid) allPerService;
            description = "Triggers each Starr service supports for this notification.";
          };

          _fieldRenames = mkOption {
            type = types.attrsOf types.str;
            readOnly = true;
            internal = true;
            default = fieldRenames;
            description = "Option names that are sent to the Starr API under a different field name.";
          };

          _omitFields = mkOption {
            type = types.listOf types.str;
            readOnly = true;
            internal = true;
            default = omitFields;
            description = "Option names that are not sent to the Starr API.";
          };

          _seerr = mkOption {
            type = types.nullOr types.raw;
            readOnly = true;
            internal = true;
            visible = false;
            default = if seerr == null then null else { hasTypes = seerrHasTypes; } // seerr;
            description = "How this connector maps onto a Seerr notification agent.";
          };

          _removedOptions = mkOption {
            type = types.attrsOf types.str;
            readOnly = true;
            internal = true;
            default = allRemovedOptions;
            description = "Removed option names, mapped to instructions for what replaces them.";
          };
        }
        // mapAttrs (
          _: instructions:
          mkOption {
            type = types.nullOr types.raw;
            default = null;
            visible = false;
            description = "Removed. ${instructions}";
          }
        ) allRemovedOptions
        // concatMapAttrs serviceBlock allPerService
        // seerrBlock
        // fieldOptions;
      }
    );
}
