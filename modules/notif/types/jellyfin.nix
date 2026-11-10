{
  config,
  lib,
  secrets,
  notifLib,
}:
with lib;
let
  triggers = {
    sonarr = {
      valid = [
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
      ];
      default = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onImportComplete"
        "onRename"
        "onSeriesAdd"
        "onSeriesDelete"
        "onEpisodeFileDelete"
        "onEpisodeFileDeleteForUpgrade"
        "onApplicationUpdate"
      ];
    };
    radarr = {
      valid = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onRename"
        "onMovieDelete"
        "onMovieFileDelete"
        "onMovieFileDeleteForUpgrade"
        "onHealthIssue"
        "onHealthRestored"
        "onApplicationUpdate"
      ];
      default = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onRename"
        "onMovieDelete"
        "onMovieFileDelete"
        "onMovieFileDeleteForUpgrade"
        "onApplicationUpdate"
      ];
    };
    lidarr = {
      valid = [
        "onGrab"
        "onReleaseImport"
        "onUpgrade"
        "onRename"
        "onArtistAdd"
        "onArtistDelete"
        "onAlbumDelete"
        "onHealthIssue"
        "onHealthRestored"
        "onTrackRetag"
        "onApplicationUpdate"
      ];
      default = [
        "onGrab"
        "onReleaseImport"
        "onUpgrade"
        "onRename"
        "onArtistAdd"
        "onArtistDelete"
        "onHealthIssue"
        "onTrackRetag"
        "onApplicationUpdate"
      ];
    };
  };
in
mkOption {
  type = notifLib.mkNotificationType {
    implementationName = "Emby / Jellyfin";

    enable = {
      default = config.nixflix.jellyfin.enable;
      defaultText = literalExpression "config.nixflix.jellyfin.enable";
    };

    dependencies.default = [ "jellyfin-api-key.service" ];

    services = {
      default = optionals config.nixflix.jellyfin.enable (
        [
          "sonarr"
          "sonarr-anime"
          "radarr"
        ]
        ++ optional (config.nixflix.jellyfin.libraries.Music or null != null) "lidarr"
      );
      defaultText = literalExpression ''
        optionals config.nixflix.jellyfin.enable (
          [ "sonarr" "sonarr-anime" "radarr" ]
          ++ optional (config.nixflix.jellyfin.libraries.Music or null != null) "lidarr"
        )
      '';
    };

    perService = mapAttrs (
      svc: t:
      {
        triggers = t;
      }
      // optionalAttrs (svc != "lidarr") {
        fields = {
          mapFrom = notifLib.field types.str "Starr path to rewrite when Jellyfin sees the library path differently (requires updateLibrary).";
          mapTo = notifLib.field types.str "Jellyfin path that mapFrom is rewritten to (requires updateLibrary).";
        };
      }
    ) triggers;
    removedOptions = {
      triggers = "Use the boolean trigger options instead, for example `nixflix.notif.jellyfin.onGrab = false;` or `nixflix.notif.jellyfin.sonarr.onImportComplete = false;`.";
    };

    extraOptions = {
      useSsl = notifLib.field types.bool "Connect to Jellyfin over HTTPS instead of HTTP.";
      urlBase = notifLib.field types.str "Prefix for the Jellyfin URL.";
      notify = notifLib.field types.bool "Have Emby send notifications to configured providers. Not supported on Jellyfin.";
      updateLibrary = notifLib.field types.bool "Update the library on import, rename or delete.";

      host = mkOption {
        type = types.str;
        description = "Host of the Jellyfin server.";
        default = config.nixflix.jellyfin.connectionAddress;
        defaultText = literalExpression "config.nixflix.jellyfin.connectionAddress";
      };

      port = mkOption {
        type = types.port;
        description = "Port of the Jellyfin server.";
        default = config.nixflix.jellyfin.network.internalHttpPort;
        defaultText = literalExpression "config.nixflix.jellyfin.network.internalHttpPort";
      };

      apiKey = secrets.mkSecretOption {
        description = "API key for Jellyfin.";
        default = config.nixflix.jellyfin.apiKey;
        defaultText = literalExpression "config.nixflix.jellyfin.apiKey";
        nullable = true;
      };
    };
  };
  default = { };
  description = "Emby/Jellyfin notification definition for Starr services.";
}
