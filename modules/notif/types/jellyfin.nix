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

    triggers = {
      type = types.submodule { options = mapAttrs (_: notifLib.mkTriggersOption) triggers; };
      default = { };
    };

    extraOptions = {
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
