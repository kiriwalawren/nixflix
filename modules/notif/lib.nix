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

  # Keyed by service, each value lists the triggers the schema marks as unsupported.
  mkTriggers = mapAttrs (
    service: unsupported: {
      valid = subtractLists unsupported allTriggers.${service};
      default = [ ];
    }
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

  mkConnectorOption =
    {
      implementationName,
      description,
      services ? allServices,
      triggers,
      fields,
    }:
    mkOption {
      type = mkNotificationType {
        inherit implementationName;
        services.default = services;
        triggers = {
          type = types.submodule { options = mapAttrs (_: mkTriggersOption) triggers; };
          default = { };
        };
        extraOptions = fields;
      };
      default = { };
      inherit description;
    };

  mkTriggersOption =
    serviceTriggers:
    mkOption {
      type = types.listOf (types.enum serviceTriggers.valid);
      inherit (serviceTriggers) default;
      description = "Starr trigger events that enable this notification.";
    };

  mkNotificationType =
    {
      implementationName,
      enable ? { },
      dependencies ? { },
      services ? { },
      triggers ? { },
      extraOptions ? { },
      imports ? [ ],
    }:
    types.submodule (
      { config, ... }: {
        inherit imports;
        freeformType = types.attrsOf types.anything;
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
              default = [ ];
              description = "Which Starr services to configure this notification on.";
            }
            // services
          );

          triggers = mkOption (
            {
              type = types.attrsOf (types.listOf types.str);
              default = { };
              description = "Starr trigger events that enable this notification, per service.";
            }
            // triggers
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
        }
        // (if isFunction extraOptions then extraOptions config else extraOptions);
      }
    );
}
