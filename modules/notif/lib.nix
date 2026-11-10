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
        ) (withSonarrAnime perService);
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
      enable ? { },
      dependencies ? { },
      services ? { },
      extraOptions ? { },
      imports ? [ ],
      legacyTriggers ? false,
      omitFields ? [ ],
      fieldRenames ? { },
    }:
    let
      allPerService = withSonarrAnime perService;
      serviceNames = attrNames allPerService;
      validOf = svc: allPerService.${svc}.triggers.valid;
      defaultOf = svc: allPerService.${svc}.triggers.default;
      isDefault = t: svc: elem t (defaultOf svc);
      sharedTriggers = filter (
        t:
        all (svc: elem t (validOf svc)) serviceNames
        && all (svc: isDefault t svc == isDefault t (head serviceNames)) serviceNames
      ) (validOf (head serviceNames));
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
              genAttrs (subtractLists sharedTriggers spec.triggers.valid) (
                t: triggerOption (elem t spec.triggers.default) "Whether to notify on ${t} from ${svc}."
              )
              // resolve (spec.fields or { }) config;
            overrides =
              mapAttrs (overrideOption svc) fieldOptions
              // genAttrs sharedTriggers (
                t: overrideOption svc t (triggerOption false "Whether to notify on ${t}.")
              );
          in
          {
            ${svc} = mkOption {
              type = types.submodule { options = overrides // ownOptions; };
              default = { };
              description = "Settings for ${svc}. Any connector-level field or trigger set here overrides it for ${svc} only.";
            };
          };
      in
      {
        inherit imports;
        options = {
          enable = mkOption (
            {
              type = types.bool;
              default = false;
              description = "Whether or not this notification is enabled.";
            }
            // enable
          );

          dependencies = mkOption (
            {
              type = types.listOf types.str;
              default = [ ];
              description = "systemd services that this integration depends on";
            }
            // dependencies
          );

          services = mkOption (
            {
              type = types.listOf types.str;
              default = serviceNames;
              description = "Which Starr services to configure this notification on.";
            }
            // services
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
        }
        // optionalAttrs legacyTriggers {
          triggers = mkOption {
            type = types.submodule {
              options = mapAttrs (
                _: spec:
                mkOption {
                  type = types.nullOr (types.listOf (types.enum spec.triggers.valid));
                  default = null;
                  description = "List of enabled triggers. Replaces the boolean trigger options for this service.";
                }
              ) (removeAttrs allPerService [ "sonarr-anime" ]);
            };
            default = { };
            visible = false;
            description = "Deprecated list form of the trigger options.";
          };
        }
        // genAttrs sharedTriggers (
          t:
          triggerOption (isDefault t (head serviceNames)) "Whether to notify on ${t} from every Starr service."
        )
        // concatMapAttrs serviceBlock allPerService
        // fieldOptions;
      }
    );
}
