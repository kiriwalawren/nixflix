{ lib, ... }:
with lib;
let
  typeOptionsModule = types.submodule {
    options = {
      type = mkOption {
        type = types.str;
        description = "The content type (e.g., 'Movie', 'Series', 'Season', 'Episode', 'MusicAlbum', 'MusicArtist', 'Audio')";
        example = "Movie";
      };
      metadataFetchers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of metadata fetchers to enable for this type";
      };
      metadataFetcherOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use metadata fetchers";
      };
      imageFetchers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of image fetchers to enable for this type";
      };
      imageFetcherOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use image fetchers";
      };
      imageOptions = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              type = mkOption {
                type = types.enum [
                  "Primary"
                  "Art"
                  "Backdrop"
                  "Banner"
                  "Logo"
                  "Thumb"
                  "Disc"
                  "Box"
                  "Screenshot"
                  "Menu"
                  "Chapter"
                  "BoxRear"
                  "Profile"
                ];
                description = "The image type";
              };
              limit = mkOption {
                type = types.int;
                default = 0;
                description = "Maximum number of images of this type (0 for unlimited)";
              };
              minWidth = mkOption {
                type = types.int;
                default = 0;
                description = "Minimum width for images of this type";
              };
            };
          }
        );
        default = [ ];
        description = "Image download options for this type";
      };
    };
  };

  libraryModule = types.submodule {
    options = {
      collectionType = mkOption {
        type = types.enum [
          "movies"
          "tvshows"
          "music"
          "musicvideos"
          "homevideos"
          "boxsets"
          "books"
          "mixed"
        ];
        description = ''
          The type of media library.
          - movies: Movie library
          - tvshows: TV Shows library
          - music: Music library
          - musicvideos: Music Videos library
          - homevideos: Home Videos (and Photos) library
          - boxsets: Box Sets library
          - books: Books library
          - mixed: Mixed Movies and TV Shows library
        '';
        example = "movies";
      };

      paths = mkOption {
        type = types.listOf types.str;
        description = "List of media folder paths for this library";
        example = [
          "/mnt/movies"
          "/media/films"
        ];
      };

      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this library is enabled";
      };

      enablePhotos = mkOption {
        type = types.bool;
        default = true;
        description = "Enable photo support in this library";
      };

      enableRealtimeMonitor = mkOption {
        type = types.bool;
        default = true;
        description = "Monitor the library folders for file changes in real-time";
      };

      enableLUFSScan = mkOption {
        type = types.bool;
        default = true;
        description = "Enable LUFS (Loudness Units Full Scale) audio normalization scanning";
      };

      enableChapterImageExtraction = mkOption {
        type = types.bool;
        default = true;
        description = "Extract chapter images from video files";
      };

      extractChapterImagesDuringLibraryScan = mkOption {
        type = types.bool;
        default = true;
        description = "Extract chapter images during library scan (vs on-demand)";
      };

      enableTrickplayImageExtraction = mkOption {
        type = types.bool;
        default = true;
        description = "Extract trickplay images (thumbnails for seeking)";
      };

      extractTrickplayImagesDuringLibraryScan = mkOption {
        type = types.bool;
        default = true;
        description = "Extract trickplay images during library scan (vs on-demand)";
      };

      saveLocalMetadata = mkOption {
        type = types.bool;
        default = true;
        description = "Save metadata to .nfo files alongside media";
      };

      enableAutomaticSeriesGrouping = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically group series together";
      };

      enableEmbeddedTitles = mkOption {
        type = types.bool;
        default = true;
        description = "Use embedded titles from media files";
      };

      enableEmbeddedExtrasTitles = mkOption {
        type = types.bool;
        default = true;
        description = "Use embedded titles for extras";
      };

      enableEmbeddedEpisodeInfos = mkOption {
        type = types.bool;
        default = true;
        description = "Use embedded episode information from media files";
      };

      automaticRefreshIntervalDays = mkOption {
        type = types.int;
        default = 0;
        description = "Days between automatic metadata refreshes (0 to disable)";
      };

      preferredMetadataLanguage = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Preferred language for metadata (e.g., 'en', 'fr', 'de')";
        example = "en";
      };

      metadataCountryCode = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Country code for metadata (e.g., 'US', 'GB', 'FR')";
        example = "US";
      };

      seasonZeroDisplayName = mkOption {
        type = types.str;
        default = "Specials";
        description = "Display name for season 0 (specials)";
      };

      metadataSavers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of metadata savers to enable";
      };

      disabledLocalMetadataReaders = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of local metadata readers to disable";
      };

      localMetadataReaderOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use local metadata readers";
      };

      disabledSubtitleFetchers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of subtitle fetchers to disable";
      };

      subtitleFetcherOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use subtitle fetchers";
      };

      skipSubtitlesIfEmbeddedSubtitlesPresent = mkOption {
        type = types.bool;
        default = true;
        description = "Skip downloading external subtitles if embedded subtitles are present";
      };

      skipSubtitlesIfAudioTrackMatches = mkOption {
        type = types.bool;
        default = true;
        description = "Skip downloading subtitles if audio track matches preferred language";
      };

      subtitleDownloadLanguages = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Languages to download subtitles for";
        example = [
          "eng"
          "fra"
        ];
      };

      requirePerfectSubtitleMatch = mkOption {
        type = types.bool;
        default = true;
        description = "Only download subtitles that perfectly match the media file";
      };

      saveSubtitlesWithMedia = mkOption {
        type = types.bool;
        default = true;
        description = "Save downloaded subtitles alongside media files";
      };

      allowEmbeddedSubtitles = mkOption {
        type = types.enum [
          "AllowAll"
          "AllowText"
          "AllowImage"
          "AllowNone"
        ];
        default = "AllowAll";
        description = ''
          Control which types of embedded subtitles to allow:
          - AllowAll: Allow all embedded subtitles
          - AllowText: Allow only text-based embedded subtitles
          - AllowImage: Allow only image-based embedded subtitles
          - AllowNone: Don't allow any embedded subtitles
        '';
      };

      saveLyricsWithMedia = mkOption {
        type = types.bool;
        default = false;
        description = "Save downloaded lyrics alongside media files";
      };

      disabledLyricFetchers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of lyric fetchers to disable";
      };

      lyricFetcherOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use lyric fetchers";
      };

      disabledMediaSegmentProviders = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of media segment providers to disable";
      };

      mediaSegmentProviderOrder = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Order in which to use media segment providers";
      };

      saveTrickplayWithMedia = mkOption {
        type = types.bool;
        default = false;
        description = "Save trickplay images alongside media files";
      };

      preferNonstandardArtistsTag = mkOption {
        type = types.bool;
        default = false;
        description = "Prefer non-standard artist tags in music files";
      };

      useCustomTagDelimiters = mkOption {
        type = types.bool;
        default = false;
        description = "Use custom tag delimiters for parsing metadata";
      };

      customTagDelimiters = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Custom delimiters for parsing tags";
      };

      delimiterWhitelist = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Whitelist of delimiters to preserve";
      };

      automaticallyAddToCollection = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically add items to collections based on metadata";
      };

      typeOptions = mkOption {
        type = types.listOf typeOptionsModule;
        default = [ ];
        description = "Content type-specific metadata and image fetcher configuration";
        example = [
          {
            type = "Movie";
            metadataFetchers = [
              "TheMovieDb"
              "The Open Movie Database"
            ];
            imageFetchers = [ "TheMovieDb" ];
          }
        ];
      };
    };
  };
in
{
  options.nixflix.jellyfin.libraries = mkOption {
    description = ''
      Jellyfin media libraries to manage declaratively.

      By default, libraries are automatically created for enabled Arr services:
      - Shows: Created when Sonarr is enabled
      - Movies: Created when Radarr is enabled
      - Music: Created when Lidarr is enabled
      - Anime: Created when either Sonarr anime or Radarr anime is enabled

      Default libraries can be removed with the following:
      - nixflix.jellyfin.libraries.Movies = lib.mkForce {};
    '';
    type = types.attrsOf libraryModule;
    default = { };
    example = {
      "Movies" = {
        collectionType = "movies";
        paths = [ "/mnt/movies" ];
        preferredMetadataLanguage = "en";
        metadataCountryCode = "US";
        enableRealtimeMonitor = true;
      };
      "Shows" = {
        collectionType = "tvshows";
        paths = [ "/mnt/tv" ];
        seasonZeroDisplayName = "Specials";
      };
      "Family Photos" = {
        collectionType = "homevideos";
        paths = [ "/mnt/photos" ];
        enablePhotos = true;
      };
    };
  };
}
