{
  jellyfin = {
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

  subsonic.lidarr = {
    valid = [
      "onGrab"
      "onReleaseImport"
      "onUpgrade"
      "onRename"
      "onArtistAdd"
      "onArtistDelete"
      "onAlbumDelete"
      "onHealthIssue"
      "onTrackRetag"
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
    ];
  };

  ntfy = {
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
}
