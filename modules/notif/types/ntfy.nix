{
  lib,
  secrets,
  notifLib,
  ...
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
        "onSeriesAdd"
        "onSeriesDelete"
        "onEpisodeFileDelete"
        "onEpisodeFileDeleteForUpgrade"
        "onHealthIssue"
        "onHealthRestored"
        "onApplicationUpdate"
        "onManualInteractionRequired"
      ];
      default = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onImportComplete"
        "onSeriesAdd"
        "onSeriesDelete"
        "onEpisodeFileDelete"
        "onEpisodeFileDeleteForUpgrade"
        "onApplicationUpdate"
        "onManualInteractionRequired"
      ];
    };
    radarr = {
      valid = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onMovieAdded"
        "onMovieDelete"
        "onMovieFileDelete"
        "onMovieFileDeleteForUpgrade"
        "onHealthIssue"
        "onHealthRestored"
        "onApplicationUpdate"
        "onManualInteractionRequired"
      ];
      default = [
        "onGrab"
        "onDownload"
        "onUpgrade"
        "onMovieAdded"
        "onMovieDelete"
        "onMovieFileDelete"
        "onMovieFileDeleteForUpgrade"
        "onApplicationUpdate"
        "onManualInteractionRequired"
      ];
    };
    lidarr = {
      valid = [
        "onGrab"
        "onReleaseImport"
        "onUpgrade"
        "onArtistAdd"
        "onArtistDelete"
        "onAlbumDelete"
        "onHealthIssue"
        "onHealthRestored"
        "onDownloadFailure"
        "onImportFailure"
        "onApplicationUpdate"
      ];
      default = [
        "onGrab"
        "onReleaseImport"
        "onUpgrade"
        "onArtistAdd"
        "onArtistDelete"
        "onHealthIssue"
        "onDownloadFailure"
        "onImportFailure"
        "onApplicationUpdate"
      ];
    };
  };
in
mkOption {
  type = notifLib.mkNotificationType {
    implementationName = "ntfy.sh";

    seerr = {
      agent = "ntfy";
      mappedFields = [
        "serverUrl"
        "topics"
        "ntfyTags"
        "userName"
        "password"
        "accessToken"
        "priority"
      ];
      fields.locale = notifLib.field types.str "Language of Seerr's notification text, for example `en`.";
      toSeerr =
        r:
        notifLib.seerrOptions r {
          url = "serverUrl";
          username = "userName";
          password = "password";
          token = "accessToken";
          priority = "priority";
          locale = "locale";
        }
        // {
          topic = head r.topics;
          tags = concatStringsSep "," (r.ntfyTags or [ ]);
          authMethodUsernamePassword = (r.userName or null) != null;
          authMethodToken = (r.accessToken or null) != null;
        };
      required = _: [ "serverUrl" ];
      checks = r: [
        {
          assertion = length r.topics == 1;
          message = "Seerr's ntfy agent publishes to a single topic; set `nixflix.notif.ntfy.seerr.topics` to exactly one topic.";
        }
      ];
    };

    perService = mapAttrs (_: t: { triggers = t; }) triggers;
    removedOptions = {
      triggers = "Use the boolean trigger options in each service block instead, for example `nixflix.notif.ntfy.sonarr.onGrab = false;`.";
      username = "It has been renamed to `nixflix.notif.ntfy.userName`.";
    };
    fieldRenames.ntfyTags = "tags";

    extraOptions = {
      serverUrl = mkOption {
        type = types.str;
        default = "https://ntfy.sh";
        description = "ntfy server URL.";
      };

      topics = secrets.mkOneOrMoreSecretsOption { description = "Topics to publish notifications to."; };

      accessToken = secrets.mkSecretOption {
        description = "Access token for the ntfy server.";
        nullable = true;
      };

      userName = secrets.mkSecretOption {
        description = "Username for the ntfy server.";
        nullable = true;
      };

      password = secrets.mkSecretOption {
        description = "Password for the ntfy server.";
        nullable = true;
      };

      priority = mkOption {
        type = types.ints.between 1 5;
        default = 3;
        description = "Priority of the notification.";
      };

      ntfyTags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Tags/emojis to include on the notification.";
      };

      clickUrl = mkOption {
        type = types.str;
        default = "";
        description = "URL to open when the notification is clicked.";
      };
    };
  };
  default = { };
  description = "ntfy notification definition for Starr services.";
}
