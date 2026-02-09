{
  lib,
  config,
  ...
}:
with lib;
let
  mkStrOption =
    default: description:
    mkOption {
      type = types.str;
      inherit default description;
    };
in
{
  options.nixflix.jellyfin.system = {
    serverName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      defaultText = literalExpression ''"''${config.networking.hostName}"'';
      description = ''
        This name will be used to identify the server and will default to the server's hostname.
      '';
    };

    # Language
    preferredMetadataLanguage = mkStrOption "en" "Display language of jellyfin.";

    metadataCountryCode = mkStrOption "US" ''
      Country code for language. Determines stuff like dates, comma placement etc.
    '';

    # Paths
    cachePath = mkOption {
      type = types.str;
      default = config.nixflix.jellyfin.cacheDir;
      defaultText = literalExpression ''"''${config.nixflix.jellyfin.cacheDir}"'';
      description = ''
        Specify a custom location for server cache files such as images.
      '';
    };

    metadataPath = mkStrOption "/var/lib/jellyfin/metadata" ''
      Specify a custom location for downloaded artwork and metadata.
    '';

    logFileRetentionDays = mkOption {
      type = types.int;
      default = 3;
      description = ''
        The amount of days that jellyfin should keep log files before deleting.
      '';
    };

    isStartupWizardCompleted = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Controls whether or not the startup wizard is marked as completed.
        Set to `false` to show the startup wizard when visiting jellyfin (not recommended as this
        will happen every time jellyfin is restarted)
      '';
    };

    enableMetrics = mkEnableOption "metrics";

    enableNormalizedItemByNameIds = mkOption {
      type = types.bool;
      default = true;
    };

    isPortAuthorized = mkOption {
      type = types.bool;
      default = true;
    };

    quickConnectAvailable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether or not to enable quickconnect
      '';
    };

    enableCaseSensitiveItemIds = mkOption {
      type = types.bool;
      default = true;
    };

    disableLiveTvChannelUserDataName = mkOption {
      type = types.bool;
      default = true;
    };

    sortReplaceCharacters = mkOption {
      type = with types; listOf str;
      default = [
        "."
        "+"
        "%"
      ];
    };

    sortRemoveCharacters = mkOption {
      type = with types; listOf str;
      default = [
        ","
        "&"
        "-"
        "{"
        "}"
        "'"
      ];
    };

    sortRemoveWords = mkOption {
      type = with types; listOf str;
      default = [
        "the"
        "a"
        "an"
      ];
    };

    # Resume
    minResumePct = mkOption {
      type = types.int;
      default = 5;
      description = ''
        Titles are assumed unplayed if stopped before this time.
      '';
    };

    maxResumePct = mkOption {
      type = types.int;
      default = 90;
      description = ''
        Titles are assumed fully played if stopped after this time.
      '';
    };

    minAudiobookResume = mkOption {
      type = types.int;
      default = 5;
      description = ''
        Titles are assumed unplayed if stopped before this time.
      '';
    };

    maxAudiobookResume = mkOption {
      type = types.int;
      default = 5;
      description = ''
        Titles are assumed fully played if stopped when the remaining duration is less than this value.
      '';
    };

    minResumeDurationSeconds = mkOption {
      type = types.int;
      default = 300;
      description = ''
        The shortest video length in seconds that will save playback location and let you resume.
      '';
    };

    inactiveSessionThreshold = mkOption {
      type = types.int;
      default = 0;
    };

    libraryMonitorDelay = mkOption {
      type = types.int;
      default = 60;
    };

    libraryUpdateDuration = mkOption {
      type = types.int;
      default = 30;
    };

    cacheSize = mkOption {
      type = types.int;
      default = 1800;
      description = ''
        Cache size in MB. Must be at least 3 due to Jellyfin's internal caching implementation.
        The default of 1800 matches Jellyfin's built-in default.
      '';
    };

    imageSavingConvention = mkOption {
      type = types.enum [
        "Legacy"
        "Compatible"
      ];
      default = "Legacy";
      description = "Specifies how images are saved. Legacy uses the old format, Compatible uses a more widely compatible format.";
    };

    metadataOptions = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            itemType = mkOption {
              type = str;
              description = "Media type (e.g., Movie, Series, MusicAlbum)";
            };
            disabledMetadataSavers = mkOption {
              type = listOf str;
              default = [ ];
              description = "List of metadata savers to disable for this media type";
            };
            localMetadataReaderOrder = mkOption {
              type = listOf str;
              default = [ ];
              description = "Priority order for reading local metadata";
            };
            disabledMetadataFetchers = mkOption {
              type = listOf str;
              default = [ ];
              description = "List of metadata fetchers to disable for this media type";
            };
            metadataFetcherOrder = mkOption {
              type = listOf str;
              default = [ ];
              description = "Priority order for fetching metadata from remote sources";
            };
            disabledImageFetchers = mkOption {
              type = listOf str;
              default = [ ];
              description = "List of image fetchers to disable for this media type";
            };
            imageFetcherOrder = mkOption {
              type = listOf str;
              default = [ ];
              description = "Priority order for fetching images from remote sources";
            };
          };
        });
      default = [
        {
          itemType = "Movie";
        }
        {
          itemType = "MusicVideo";
          disabledMetadataFetchers = [ "The Open Movie Database" ];
          disabledImageFetchers = [ "The Open Movie Database" ];
        }
        {
          itemType = "Series";
        }
        {
          itemType = "MusicAlbum";
          disabledMetadataFetchers = [ "TheAudioDB" ];
        }
        {
          itemType = "MusicArtist";
          disabledMetadataFetchers = [ "TheAudioDB" ];
        }
        {
          itemType = "BoxSet";
        }
        {
          itemType = "Season";
        }
        {
          itemType = "Episode";
        }
      ];
      description = ''
        Configure metadata fetching options for different media types.
        Each entry specifies which metadata and image sources to use or disable.
      '';
    };

    skipDeserializationForBasicTypes = mkOption {
      type = types.bool;
      default = true;
    };

    uiCulture = mkOption {
      type = types.str;
      default = "en-US";
    };

    saveMetadataHidden = mkEnableOption "";

    contentTypes = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            name = mkOption {
              type = str;
              description = "Content type name";
            };
            value = mkOption {
              type = str;
              description = "Content type value";
            };
          };
        });
      default = [ ];
    };

    remoteClientBitrateLimit = mkOption {
      type = types.int;
      default = 0;
    };

    enableFolderView = mkEnableOption "";

    enableGroupingMoviesIntoCollections = mkEnableOption "grouping movies into collections";

    enableGroupingShowsIntoCollections = mkEnableOption "grouping shows into collections";

    displaySpecialsWithinSeasons = mkOption {
      type = types.bool;
      default = true;
    };

    codecsUsed = mkOption {
      type = with types; listOf str;
      default = [ ];
    };

    pluginRepositories = mkOption {
      type = with types; listOf attrs;
      default = [
        {
          tag = "RepositoryInfo";
          content = {
            name = "Jellyfin Stable";
            url = "https://repo.jellyfin.org/files/plugin/manifest.json";
            enabled = true;
          };
        }
      ];
      description = "Configure which plugin repositories you use.";
    };

    enableExternalContentInSuggestions = mkOption {
      type = types.bool;
      default = true;
    };

    imageExtractionTimeoutMs = mkOption {
      type = types.int;
      default = 0;
      description = "Leave at 0 for no timeout";
    };

    pathSubstitutions = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            from = mkOption {
              type = str;
              description = "Path to substitute from";
            };
            to = mkOption {
              type = str;
              description = "Path to substitute to";
            };
          };
        });
      default = [ ];
    };

    enableSlowResponseWarning = mkOption {
      type = types.bool;
      default = true;
    };

    slowResponseThresholdMs = mkOption {
      type = types.int;
      default = 500;
      description = "How slow (in ms) would a response have to be before a warning is shown";
    };

    corsHosts = mkOption {
      type = with types; listOf str;
      default = [
        "*"
      ];
    };

    activityLogRetentionDays = mkOption {
      type = types.nullOr types.int;
      default = 30;
      description = "Number of days to retain activity logs. Set to null to never delete.";
    };

    libraryScanFanoutConcurrency = mkOption {
      type = types.int;
      default = 0;
      description = ''
        Maximum number of parallel tasks during library scans.
        Setting this to 0 will choose a limit based on your systems core count.

        !!! warning

            Setting this number too high may cause issues with network file systems; if you encounter problems lower this number.
      '';
    };

    libraryMetadataRefreshConcurrency = mkOption {
      type = types.int;
      default = 0;
      description = ''
        Maximum number of parallel tasks during library scans.
        Setting this to 0 will choose a limit based on your systems core count.

        !!! warning

            Setting this number too high may cause issues with network file systems; if you encounter problems lower this number.
      '';
    };

    removeOldPlugins = mkOption {
      type = types.bool;
      default = true;
    };

    allowClientLogUpload = mkOption {
      type = types.bool;
      default = true;
    };

    dummyChapterDuration = mkOption {
      type = types.int;
      default = 0;
    };

    chapterImageResolution = mkOption {
      type = types.enum [
        "MatchSource"
        "P2160"
        "P1440"
        "P1080"
        "P720"
        "P480"
        "P360"
        "P240"
        "P144"
      ];
      default = "MatchSource";
      description = ''
        The resolution of the extracted chapter images.
        Changing this will have no effect on existing dummy chapters.
      '';
    };

    parallelImageEncodingLimit = mkOption {
      type = types.int;
      default = 0;
      description = ''
        Maximum number of image encodings that are allowed to run in parallel.
        Setting this to 0 will choose a limit based on your systems core count.
      '';
    };

    castReceiverApplications = mkOption {
      type =
        with types;
        listOf (submodule {
          options = {
            id = mkOption {
              type = str;
              description = "Cast receiver application ID";
            };
            name = mkOption {
              type = str;
              description = "Display name for the cast receiver";
            };
          };
        });
      default = [
        {
          id = "F007D354";
          name = "Stable";
        }
        {
          id = "6F511C87";
          name = "Unstable";
        }
      ];
    };

    trickplayOptions = {
      enableHwAcceleration = mkEnableOption "hardware acceleration";

      enableHwEncoding = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to enable hardware encoding.

          Currently only available on QSV, VA-API, VideoToolbox and RKMPP, this option has no effect on other hardware acceleration methods.
        '';
      };

      enableKeyFrameOnlyExtraction = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to enable key frame only extraction.

          Extract key frames only for significantly faster processing with less accurate timing.
          If the configured hardware decoder does not support this mode, will use the software decoder instead.
        '';
      };

      scanBehavior = mkOption {
        type = types.enum [
          "NonBlocking"
          "Blocking"
        ];
        default = "NonBlocking";
        description = ''
          The default behavior is non blocking, which will add media to the library before trickplay generation is done. Blocking will ensure trickplay files are generated before media is added to the library, but will make scans significantly longer.
        '';
      };

      processPriority = mkOption {
        type = types.enum [
          "High"
          "AboveNormal"
          "Normal"
          "BelowNormal"
          "Idle"
        ];
        default = "BelowNormal";
        description = ''
          Setting this lower or higher will determine how the CPU prioritizes the ffmpeg trickplay generation process in relation to other processes.
          If you notice slowdown while generating trickplay images but don't want to fully stop their generation, try lowering this as well as the thread count.
        '';
      };

      interval = mkOption {
        type = types.int;
        default = 10000;
        description = ''
          Interval of time (ms) between each new trickplay image.
        '';
      };

      widthResolutions = mkOption {
        type = with types; listOf int;
        default = [ 320 ];
        description = ''
          List of the widths (px) that trickplay images will be generated at.
          All images should generate proportionally to the source, so a width of 320 on a 16:9 video ends up around 320x180.
        '';
      };

      tileWidth = mkOption {
        type = types.int;
        default = 10;
        description = ''
          Maximum number of images per tile in the X direction.
        '';
      };

      tileHeight = mkOption {
        type = types.int;
        default = 10;
        description = ''
          Maximum number of images per tile in the X direction.
        '';
      };

      qscale = mkOption {
        type = types.ints.between 2 31;
        default = 4;
        description = ''
          The quality scale of images output by ffmpeg, with 2 being the highest quality and 31 being the lowest.
        '';
      };

      jpegQuality = mkOption {
        type = types.ints.between 0 100;
        default = 90;
        description = ''
          The JPEG compression quality for trickplay images.
        '';
      };

      processThreads = mkOption {
        type = types.int;
        default = 1;
        description = ''
          The number of threads to pass to the '-threads' argument of ffmpeg.
        '';
      };
    };

    enableLegacyAuthorization = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable legacy authorization mode for backwards compatibility.
      '';
    };
  };
}
