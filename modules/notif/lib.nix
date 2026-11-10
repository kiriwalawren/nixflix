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

  expandServices = concatMap (
    s:
    if s == "sonarr" then
      [
        "sonarr"
        "sonarr-anime"
      ]
    else
      [ s ]
  );

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
    }:
    mkOption {
      type = mkNotificationType {
        inherit implementationName;
        perService = mapAttrs (
          svc: spec:
          let
            valid = subtractLists (spec.unsupportedTriggers or [ ]) allTriggers.${svc};
          in
          {
            triggers = {
              inherit valid;
              default = subtractLists uiDefaultOff.${svc} valid;
            };
            fields = spec.fields or { };
          }
        ) perService;
        extraOptions = fields;
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
    }:
    let
      serviceNames = attrNames perService;
      validOf = svc: perService.${svc}.triggers.valid;
      defaultOf = svc: perService.${svc}.triggers.default;
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
        serviceBlock =
          svc: spec:
          let
            options =
              genAttrs (subtractLists sharedTriggers spec.triggers.valid) (
                t: triggerOption (elem t spec.triggers.default) "Whether to notify on ${t} from ${svc}."
              )
              // resolve (spec.fields or { }) config;
          in
          optionalAttrs (options != { }) {
            ${svc} = mkOption {
              type = types.submodule { inherit options; };
              default = { };
              description = "Settings that only apply to ${svc}.";
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
              default = expandServices serviceNames;
              description = "Which Starr services to configure this notification on.";
            }
            // services
          );

          name = mkOption {
            type = types.str;
            default = implementationName;
            description = "User-defined name for the notification instance.";
          };

          implementationName = mkOption {
            type = types.str;
            readOnly = true;
            default = implementationName;
            description = "Type of notification to configure (matches schema implementationName).";
          };

          includeHealthWarnings = field types.bool "Include health warnings, not only errors, in health notifications.";

          _supportedTriggers = mkOption {
            type = types.attrsOf (types.listOf types.str);
            readOnly = true;
            internal = true;
            default = mapAttrs (_: spec: spec.triggers.valid) perService;
            description = "Triggers each Starr service supports for this notification.";
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
              ) perService;
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
        // concatMapAttrs serviceBlock perService
        // resolve extraOptions config;
      }
    );
}
