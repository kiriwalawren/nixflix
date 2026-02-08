{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-users";

  nodes.machine = {...}: {
    imports = [nixosModules];

    virtualisation = {
      diskSize = 3 * 1024;
      cores = 4;
    };

    nixflix = {
      enable = true;

      jellyfin = {
        enable = true;

        users = {
          admin = {
            password = {_secret = pkgs.writeText "kiri_password" "321password";};
            policy.isAdministrator = true;
          };

          kiri = {
            password = "password123";
            enableAutoLogin = false;
            mutable = false;

            configuration = {
              audioLanguagePreference = "eng";
              playDefaultAudioTrack = false;
              subtitleLanguagePreference = "spa";
              displayMissingEpisodes = true;
              subtitleMode = "Always";
              displayCollectionsView = true;
              enableLocalPassword = true;
              hidePlayedInLatest = false;
              rememberAudioSelections = false;
              rememberSubtitleSelections = false;
              enableNextEpisodeAutoPlay = false;
            };

            policy = {
              isAdministrator = false;
              isHidden = false;
              isDisabled = false;
              enableAllChannels = false;
              enableAllDevices = false;
              enableAllFolders = false;
              enableAudioPlaybackTranscoding = false;
              enableCollectionManagement = true;
              enableContentDeletion = true;
              enableContentDownloading = false;
              enableLiveTvAccess = false;
              enableLiveTvManagement = false;
              enableMediaConversion = false;
              enableMediaPlayback = true;
              enablePlaybackRemuxing = false;
              enablePublicSharing = false;
              enableRemoteAccess = true;
              enableRemoteControlOfOtherUsers = true;
              enableSharedDeviceControl = false;
              enableSubtitleManagement = true;
              enableSyncTranscoding = false;
              enableVideoPlaybackTranscoding = false;
              forceRemoteSourceTranscoding = true;
              maxParentalRating = 18;
              blockedTags = ["violence" "horror"];
              allowedTags = ["comedy" "drama"];
              blockUnratedItems = ["Movie" "Series"];
              enableUserPreferenceAccess = false;
              invalidLoginAttemptCount = 5;
              loginAttemptsBeforeLockout = 5;
              maxActiveSessions = 3;
              remoteClientBitrateLimit = 8000000;
              syncPlayAccess = "JoinGroups";
              authenticationProviderId = "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider";
              passwordResetProviderId = "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider";
              maxParentalSubRating = 10;
            };
          };
        };

        system = {
          serverName = "test-jellyfin-server";
          preferredMetadataLanguage = "de";
          metadataCountryCode = "DE";
          uiCulture = "de-DE";
          logFileRetentionDays = 7;
          activityLogRetentionDays = 60;
          enableMetrics = true;
          enableNormalizedItemByNameIds = false;
          isPortAuthorized = false;
          quickConnectAvailable = false;
          enableCaseSensitiveItemIds = false;
          disableLiveTvChannelUserDataName = false;
          sortReplaceCharacters = ["-" "_"];
          sortRemoveCharacters = ["!" "?"];
          sortRemoveWords = ["der" "die" "das"];
          minResumePct = 10;
          maxResumePct = 85;
          minAudiobookResume = 2;
          maxAudiobookResume = 3;
          minResumeDurationSeconds = 120;
          inactiveSessionThreshold = 15;
          libraryMonitorDelay = 30;
          libraryUpdateDuration = 45;
          cacheSize = 500;
          imageSavingConvention = "Compatible";
          imageExtractionTimeoutMs = 5000;
          skipDeserializationForBasicTypes = false;
          saveMetadataHidden = true;
          enableFolderView = true;
          enableGroupingMoviesIntoCollections = true;
          enableGroupingShowsIntoCollections = true;
          displaySpecialsWithinSeasons = false;
          remoteClientBitrateLimit = 8000000;
          enableSlowResponseWarning = false;
          slowResponseThresholdMs = 1000;
          corsHosts = ["localhost" "test.example.com"];
          libraryScanFanoutConcurrency = 2;
          libraryMetadataRefreshConcurrency = 4;
          allowClientLogUpload = false;
          enableExternalContentInSuggestions = false;
          dummyChapterDuration = 10;
          chapterImageResolution = "P720";
          parallelImageEncodingLimit = 3;
          castReceiverApplications = [
            {
              id = "CUSTOM123";
              name = "Test Receiver";
            }
          ];
          trickplayOptions = {
            enableHwAcceleration = true;
            enableHwEncoding = true;
            enableKeyFrameOnlyExtraction = true;
            scanBehavior = "Blocking";
            processPriority = "Normal";
            interval = 5000;
            widthResolutions = [320 480 720];
            tileWidth = 8;
            tileHeight = 8;
            qscale = 6;
            jpegQuality = 85;
            processThreads = 2;
          };
          metadataOptions = [
            {
              itemType = "Movie";
              disabledMetadataSavers = ["Nfo"];
              disabledMetadataFetchers = ["TheMovieDb"];
              localMetadataReaderOrder = ["Nfo"];
              metadataFetcherOrder = ["TheMovieDb"];
              disabledImageFetchers = ["TheMovieDb"];
              imageFetcherOrder = ["TheMovieDb"];
            }
          ];
          contentTypes = [
            {
              name = "test";
              value = "application/test";
            }
          ];
          pathSubstitutions = [
            {
              from = "/old/path";
              to = "/new/path";
            }
          ];
          codecsUsed = ["h264" "hevc"];
          pluginRepositories = [
            {
              tag = "RepositoryInfo";
              content = {
                name = "Test Repo";
                url = "https://test.example.com/manifest.json";
                enabled = true;
              };
            }
          ];
          enableLegacyAuthorization = false;
        };

        encoding = {
          enableHardwareEncoding = false;
          allowHevcEncoding = true;
          allowAv1Encoding = true;
          encodingThreadCount = 4;
          transcodingTempPath = "/custom/transcode/path";
          enableAudioVbr = true;
          downMixAudioBoost = 3;
          downMixStereoAlgorithm = "Rfc7845";
          maxMuxingQueueSize = 4096;
          enableThrottling = true;
          throttleDelaySeconds = 120;
          enableSegmentDeletion = true;
          segmentKeepSeconds = 600;
          hardwareAccelerationType = "vaapi";
          vaapiDevice = "/dev/dri/renderD129";
          enableTonemapping = true;
          tonemappingAlgorithm = "hable";
          tonemappingMode = "rgb";
          tonemappingRange = "pc";
          tonemappingDesat = 0.5;
          tonemappingPeak = 200;
          tonemappingParam = 1.5;
          h264Crf = 20;
          h265Crf = 25;
          encoderPreset = "placebo";
          deinterlaceDoubleRate = true;
          deinterlaceMethod = "bwdif";
          enableDecodingColorDepth10Hevc = false;
          enableDecodingColorDepth10Vp9 = false;
          hardwareDecodingCodecs = ["h264" "hevc" "vp9" "av1"];
          enableSubtitleExtraction = false;
          allowOnDemandMetadataBasedKeyframeExtractionForExtensions = ["mkv" "mp4"];
        };

        branding = {
          customCss = ''
            body {
              background-color: #1a1a2e;
            }
            .headerTop {
              background-color: #16213e;
            }
          '';
          loginDisclaimer = ''
            This is a test Jellyfin server.
            Please use your assigned credentials.
          '';
          splashscreenEnabled = true;
          splashscreenLocation =
            pkgs.runCommand "test-splashscreen.png" {
              buildInputs = [pkgs.imagemagick];
            } ''
              magick -size 1920x1080 xc:#1a1a2e $out
            '';
        };

        libraries = {
          "Test Movies" = {
            collectionType = "movies";
            paths = ["/media/movies" "/media/films"];
            enabled = true;
            enablePhotos = false;
            enableRealtimeMonitor = false;
            enableLUFSScan = false;
            enableChapterImageExtraction = false;
            extractChapterImagesDuringLibraryScan = false;
            saveLocalMetadata = false;
            enableAutomaticSeriesGrouping = false;
            enableEmbeddedTitles = false;
            enableEmbeddedExtrasTitles = false;
            enableEmbeddedEpisodeInfos = false;
            automaticRefreshIntervalDays = 90;
            preferredMetadataLanguage = "en";
            metadataCountryCode = "US";
            seasonZeroDisplayName = "Extras";
            metadataSavers = ["Nfo"];
            disabledLocalMetadataReaders = ["Nfo"];
            localMetadataReaderOrder = ["Nfo"];
            disabledSubtitleFetchers = ["Open Subtitles"];
            subtitleFetcherOrder = ["Open Subtitles"];
            skipSubtitlesIfEmbeddedSubtitlesPresent = false;
            skipSubtitlesIfAudioTrackMatches = false;
            subtitleDownloadLanguages = ["eng" "spa" "fra"];
            requirePerfectSubtitleMatch = false;
            saveSubtitlesWithMedia = false;
            allowEmbeddedSubtitles = "AllowText";
            automaticallyAddToCollection = false;
          };

          "Test Music" = {
            collectionType = "music";
            paths = ["/media/music"];
            enabled = true;
            preferNonstandardArtistsTag = true;
            useCustomTagDelimiters = true;
            customTagDelimiters = [";" "|"];
            saveLyricsWithMedia = true;
            disabledLyricFetchers = [];
            lyricFetcherOrder = ["LrcLib"];
            disabledMediaSegmentProviders = [];
            mediaSegmentProviderOrder = ["ChapterDb"];
            typeOptions = [
              {
                type = "MusicAlbum";
                metadataFetchers = ["TheAudioDB" "MusicBrainz"];
                metadataFetcherOrder = ["TheAudioDB" "MusicBrainz"];
                imageFetchers = ["TheAudioDB"];
                imageFetcherOrder = ["TheAudioDB"];
                imageOptions = [
                  {
                    type = "Primary";
                    limit = 1;
                    minWidth = 300;
                  }
                  {
                    type = "Backdrop";
                    limit = 3;
                    minWidth = 1920;
                  }
                ];
              }
            ];
          };
        };
      };
    };
  };

  testScript = ''
    start_all()

    port = 8096
    machine.wait_for_unit("jellyfin.service", timeout=180)
    machine.wait_for_open_port(port, timeout=180)

    # Wait for configuration services to complete
    machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=180)
    machine.wait_for_unit("jellyfin-users-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=180)
    machine.wait_for_unit("jellyfin-system-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-encoding-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-branding-config.service", timeout=180)

    api_token = machine.succeed("cat /run/jellyfin/auth-token")
    auth_header = f'"Authorization: MediaBrowser Client=\"nixflix\", Device=\"NixOS\", DeviceId=\"nixflix-auth\", Version=\"1.0.0\", Token=\"{api_token}\""'
    base_url = f'http://127.0.0.1:{port}'

    # Test API connectivity
    machine.succeed(f'curl -f -H {auth_header} {base_url}/System/Info')

    import json
    users = json.loads(machine.succeed(f'curl -f -H {auth_header} {base_url}/Users'))
    assert len(users) == 2, f"Expected 2 users, found {len(users)}"

    # Find the admin user
    kiri_users = [u for u in users if u['Name'] == 'kiri']
    assert len(kiri_users) == 1, f"Expected 1 admin user, found {len(kiri_users)}"
    user = kiri_users[0]

    assert user['EnableAutoLogin'] == False, f"EnableAutoLogin should be False, got {user['EnableAutoLogin']}"

    config = user['Configuration']
    assert config['AudioLanguagePreference'] == 'eng', f"AudioLanguagePreference should be 'eng', got {config.get('AudioLanguagePreference')}"
    assert config['PlayDefaultAudioTrack'] == False, f"PlayDefaultAudioTrack should be False, got {config['PlayDefaultAudioTrack']}"
    assert config['SubtitleLanguagePreference'] == 'spa', f"SubtitleLanguagePreference should be 'spa', got {config.get('SubtitleLanguagePreference')}"
    assert config['DisplayMissingEpisodes'] == True, f"DisplayMissingEpisodes should be True, got {config['DisplayMissingEpisodes']}"
    assert config['SubtitleMode'] == 'Always', f"SubtitleMode should be 'Always', got {config['SubtitleMode']}"
    assert config['DisplayCollectionsView'] == True, f"DisplayCollectionsView should be True, got {config['DisplayCollectionsView']}"
    assert config['EnableLocalPassword'] == True, f"EnableLocalPassword should be True, got {config['EnableLocalPassword']}"
    assert config['HidePlayedInLatest'] == False, f"HidePlayedInLatest should be False, got {config['HidePlayedInLatest']}"
    assert config['RememberAudioSelections'] == False, f"RememberAudioSelections should be False, got {config['RememberAudioSelections']}"
    assert config['RememberSubtitleSelections'] == False, f"RememberSubtitleSelections should be False, got {config['RememberSubtitleSelections']}"
    assert config['EnableNextEpisodeAutoPlay'] == False, f"EnableNextEpisodeAutoPlay should be False, got {config['EnableNextEpisodeAutoPlay']}"

    policy = user['Policy']
    assert policy['IsAdministrator'] == False, f"IsAdministrator should be False, got {policy['IsAdministrator']}"
    assert policy['IsHidden'] == False, f"IsHidden should be False, got {policy['IsHidden']}"
    assert policy['IsDisabled'] == False, f"IsDisabled should be False, got {policy['IsDisabled']}"
    assert policy['EnableAllChannels'] == False, f"EnableAllChannels should be False, got {policy['EnableAllChannels']}"
    assert policy['EnableAllDevices'] == False, f"EnableAllDevices should be False, got {policy['EnableAllDevices']}"
    assert policy['EnableAllFolders'] == False, f"EnableAllFolders should be False, got {policy['EnableAllFolders']}"
    assert policy['EnableAudioPlaybackTranscoding'] == False, f"EnableAudioPlaybackTranscoding should be False, got {policy['EnableAudioPlaybackTranscoding']}"
    assert policy['EnableCollectionManagement'] == True, f"EnableCollectionManagement should be True, got {policy['EnableCollectionManagement']}"
    assert policy['EnableContentDeletion'] == True, f"EnableContentDeletion should be True, got {policy['EnableContentDeletion']}"
    assert policy['EnableContentDownloading'] == False, f"EnableContentDownloading should be False, got {policy['EnableContentDownloading']}"
    assert policy['EnableLiveTvAccess'] == False, f"EnableLiveTvAccess should be False, got {policy['EnableLiveTvAccess']}"
    assert policy['EnableLiveTvManagement'] == False, f"EnableLiveTvManagement should be False, got {policy['EnableLiveTvManagement']}"
    assert policy['EnableMediaConversion'] == False, f"EnableMediaConversion should be False, got {policy['EnableMediaConversion']}"
    assert policy['EnableMediaPlayback'] == True, f"EnableMediaPlayback should be True, got {policy['EnableMediaPlayback']}"
    assert policy['EnablePlaybackRemuxing'] == False, f"EnablePlaybackRemuxing should be False, got {policy['EnablePlaybackRemuxing']}"
    assert policy['EnablePublicSharing'] == False, f"EnablePublicSharing should be False, got {policy['EnablePublicSharing']}"
    assert policy['EnableRemoteAccess'] == True, f"EnableRemoteAccess should be True, got {policy['EnableRemoteAccess']}"
    assert policy['EnableRemoteControlOfOtherUsers'] == True, f"EnableRemoteControlOfOtherUsers should be True, got {policy['EnableRemoteControlOfOtherUsers']}"
    assert policy['EnableSharedDeviceControl'] == False, f"EnableSharedDeviceControl should be False, got {policy['EnableSharedDeviceControl']}"
    assert policy['EnableSubtitleManagement'] == True, f"EnableSubtitleManagement should be True, got {policy['EnableSubtitleManagement']}"
    assert policy['EnableSyncTranscoding'] == False, f"EnableSyncTranscoding should be False, got {policy['EnableSyncTranscoding']}"
    assert policy['EnableVideoPlaybackTranscoding'] == False, f"EnableVideoPlaybackTranscoding should be False, got {policy['EnableVideoPlaybackTranscoding']}"
    assert policy['ForceRemoteSourceTranscoding'] == True, f"ForceRemoteSourceTranscoding should be True, got {policy['ForceRemoteSourceTranscoding']}"
    assert policy['MaxParentalRating'] == 18, f"MaxParentalRating should be 18, got {policy.get('MaxParentalRating')}"
    assert set(policy['BlockedTags']) == {'violence', 'horror'}, f"BlockedTags should be ['violence', 'horror'], got {policy['BlockedTags']}"
    assert set(policy['AllowedTags']) == {'comedy', 'drama'}, f"AllowedTags should be ['comedy', 'drama'], got {policy['AllowedTags']}"
    assert set(policy['BlockUnratedItems']) == {'Movie', 'Series'}, f"BlockUnratedItems should be ['Movie', 'Series'], got {policy['BlockUnratedItems']}"
    assert policy['EnableUserPreferenceAccess'] == False, f"EnableUserPreferenceAccess should be False, got {policy['EnableUserPreferenceAccess']}"
    assert policy['InvalidLoginAttemptCount'] == 5, f"InvalidLoginAttemptCount should be 5, got {policy['InvalidLoginAttemptCount']}"
    assert policy['LoginAttemptsBeforeLockout'] == 5, f"LoginAttemptsBeforeLockout should be 5, got {policy['LoginAttemptsBeforeLockout']}"
    assert policy['MaxActiveSessions'] == 3, f"MaxActiveSessions should be 3, got {policy['MaxActiveSessions']}"
    assert policy['RemoteClientBitrateLimit'] == 8000000, f"RemoteClientBitrateLimit should be 8000000, got {policy['RemoteClientBitrateLimit']}"
    assert policy['SyncPlayAccess'] == 'JoinGroups', f"SyncPlayAccess should be 'JoinGroups', got {policy['SyncPlayAccess']}"
    assert policy['AuthenticationProviderId'] == 'Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider', "AuthenticationProviderId mismatch"
    assert policy['PasswordResetProviderId'] == 'Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider', "PasswordResetProviderId mismatch"
    assert policy['MaxParentalSubRating'] == 10, f"MaxParentalSubRating should be 10, got {policy.get('MaxParentalSubRating')}"

    print("Testing library configuration...")

    libraries_json = machine.succeed(f'curl -f -H {auth_header} {base_url}/Library/VirtualFolders')
    libraries = json.loads(libraries_json)

    assert len(libraries) == 2, f"Expected 2 libraries, found {len(libraries)}"

    movies_libs = [lib for lib in libraries if lib['Name'] == 'Test Movies']
    assert len(movies_libs) == 1, f"Expected 1 'Test Movies' library, found {len(movies_libs)}"
    movies_lib = movies_libs[0]

    music_libs = [lib for lib in libraries if lib['Name'] == 'Test Music']
    assert len(music_libs) == 1, f"Expected 1 'Test Music' library, found {len(music_libs)}"
    music_lib = music_libs[0]

    assert movies_lib['CollectionType'] == 'movies', f"Expected collection type 'movies', got {movies_lib['CollectionType']}"
    assert set([loc['Path'] for loc in movies_lib['LibraryOptions']['PathInfos']]) == {'/media/movies', '/media/films'}, \
        f"Expected paths ['/media/movies', '/media/films'], got {[loc['Path'] for loc in movies_lib['LibraryOptions']['PathInfos']]}"

    opts = movies_lib['LibraryOptions']

    assert opts['EnablePhotos'] == False, f"EnablePhotos should be False, got {opts['EnablePhotos']}"
    assert opts['EnableRealtimeMonitor'] == False, f"EnableRealtimeMonitor should be False, got {opts['EnableRealtimeMonitor']}"
    assert opts['EnableLUFSScan'] == False, f"EnableLUFSScan should be False, got {opts['EnableLUFSScan']}"
    assert opts['EnableChapterImageExtraction'] == False, f"EnableChapterImageExtraction should be False, got {opts['EnableChapterImageExtraction']}"
    assert opts['ExtractChapterImagesDuringLibraryScan'] == False, f"ExtractChapterImagesDuringLibraryScan should be False, got {opts['ExtractChapterImagesDuringLibraryScan']}"
    assert opts['SaveLocalMetadata'] == False, f"SaveLocalMetadata should be False, got {opts['SaveLocalMetadata']}"
    assert opts['EnableAutomaticSeriesGrouping'] == False, f"EnableAutomaticSeriesGrouping should be False, got {opts['EnableAutomaticSeriesGrouping']}"
    assert opts['EnableEmbeddedTitles'] == False, f"EnableEmbeddedTitles should be False, got {opts['EnableEmbeddedTitles']}"
    assert opts['EnableEmbeddedExtrasTitles'] == False, f"EnableEmbeddedExtrasTitles should be False, got {opts['EnableEmbeddedExtrasTitles']}"
    assert opts['EnableEmbeddedEpisodeInfos'] == False, f"EnableEmbeddedEpisodeInfos should be False, got {opts['EnableEmbeddedEpisodeInfos']}"
    assert opts['SkipSubtitlesIfEmbeddedSubtitlesPresent'] == False, f"SkipSubtitlesIfEmbeddedSubtitlesPresent should be False, got {opts['SkipSubtitlesIfEmbeddedSubtitlesPresent']}"
    assert opts['SkipSubtitlesIfAudioTrackMatches'] == False, f"SkipSubtitlesIfAudioTrackMatches should be False, got {opts['SkipSubtitlesIfAudioTrackMatches']}"
    assert opts['RequirePerfectSubtitleMatch'] == False, f"RequirePerfectSubtitleMatch should be False, got {opts['RequirePerfectSubtitleMatch']}"
    assert opts['SaveSubtitlesWithMedia'] == False, f"SaveSubtitlesWithMedia should be False, got {opts['SaveSubtitlesWithMedia']}"
    assert opts['AutomaticallyAddToCollection'] == False, f"AutomaticallyAddToCollection should be False, got {opts['AutomaticallyAddToCollection']}"

    assert opts['PreferredMetadataLanguage'] == 'en', f"PreferredMetadataLanguage should be 'en', got {opts.get('PreferredMetadataLanguage')}"
    assert opts['MetadataCountryCode'] == 'US', f"MetadataCountryCode should be 'US', got {opts.get('MetadataCountryCode')}"
    assert opts['SeasonZeroDisplayName'] == 'Extras', f"SeasonZeroDisplayName should be 'Extras', got {opts['SeasonZeroDisplayName']}"

    assert opts['AutomaticRefreshIntervalDays'] == 90, f"AutomaticRefreshIntervalDays should be 90, got {opts['AutomaticRefreshIntervalDays']}"

    assert opts['AllowEmbeddedSubtitles'] == 'AllowText', f"AllowEmbeddedSubtitles should be 'AllowText', got {opts['AllowEmbeddedSubtitles']}"

    assert opts['MetadataSavers'] == ['Nfo'], f"MetadataSavers should be ['Nfo'], got {opts.get('MetadataSavers')}"
    assert opts['DisabledLocalMetadataReaders'] == ['Nfo'], f"DisabledLocalMetadataReaders should be ['Nfo'], got {opts.get('DisabledLocalMetadataReaders')}"
    assert opts['LocalMetadataReaderOrder'] == ['Nfo'], f"LocalMetadataReaderOrder should be ['Nfo'], got {opts.get('LocalMetadataReaderOrder')}"
    assert opts['DisabledSubtitleFetchers'] == ['Open Subtitles'], f"DisabledSubtitleFetchers should be ['Open Subtitles'], got {opts.get('DisabledSubtitleFetchers')}"
    assert opts['SubtitleFetcherOrder'] == ['Open Subtitles'], f"SubtitleFetcherOrder should be ['Open Subtitles'], got {opts.get('SubtitleFetcherOrder')}"
    assert set(opts['SubtitleDownloadLanguages']) == {'eng', 'spa', 'fra'}, f"SubtitleDownloadLanguages should be ['eng', 'spa', 'fra'], got {opts.get('SubtitleDownloadLanguages')}"

    assert music_lib['CollectionType'] == 'music', f"Expected collection type 'music', got {music_lib['CollectionType']}"
    assert [loc['Path'] for loc in music_lib['LibraryOptions']['PathInfos']] == ['/media/music'], \
        f"Expected paths ['/media/music'], got {[loc['Path'] for loc in music_lib['LibraryOptions']['PathInfos']]}"

    music_opts = music_lib['LibraryOptions']

    assert music_opts['PreferNonstandardArtistsTag'] == True, f"PreferNonstandardArtistsTag should be True, got {music_opts['PreferNonstandardArtistsTag']}"
    assert music_opts['UseCustomTagDelimiters'] == True, f"UseCustomTagDelimiters should be True, got {music_opts['UseCustomTagDelimiters']}"
    assert set(music_opts['CustomTagDelimiters']) == {';', '|'}, f"CustomTagDelimiters should be [';', '|'], got {music_opts.get('CustomTagDelimiters')}"

    assert music_opts['SaveLyricsWithMedia'] == True, f"SaveLyricsWithMedia should be True, got {music_opts['SaveLyricsWithMedia']}"
    assert music_opts['LyricFetcherOrder'] == ['LrcLib'], f"LyricFetcherOrder should be ['LrcLib'], got {music_opts.get('LyricFetcherOrder')}"

    assert music_opts['MediaSegmentProviderOrder'] == ['ChapterDb'], f"MediaSegmentProviderOrder should be ['ChapterDb'], got {music_opts.get('MediaSegmentProviderOrder')}"

    assert len(music_opts['TypeOptions']) == 1, f"Expected 1 TypeOptions entry, got {len(music_opts.get('TypeOptions', []))}"
    type_opt = music_opts['TypeOptions'][0]

    assert type_opt['Type'] == 'MusicAlbum', f"TypeOptions type should be 'MusicAlbum', got {type_opt.get('Type')}"
    assert type_opt['MetadataFetchers'] == ['TheAudioDB', 'MusicBrainz'], f"MetadataFetchers should be ['TheAudioDB', 'MusicBrainz'], got {type_opt.get('MetadataFetchers')}"
    assert type_opt['MetadataFetcherOrder'] == ['TheAudioDB', 'MusicBrainz'], f"MetadataFetcherOrder should be ['TheAudioDB', 'MusicBrainz'], got {type_opt.get('MetadataFetcherOrder')}"
    assert type_opt['ImageFetchers'] == ['TheAudioDB'], f"ImageFetchers should be ['TheAudioDB'], got {type_opt.get('ImageFetchers')}"
    assert type_opt['ImageFetcherOrder'] == ['TheAudioDB'], f"ImageFetcherOrder should be ['TheAudioDB'], got {type_opt.get('ImageFetcherOrder')}"

    assert len(type_opt['ImageOptions']) == 2, f"Expected 2 ImageOptions entries, got {len(type_opt.get('ImageOptions', []))}"

    img_opt_primary = [io for io in type_opt['ImageOptions'] if io['Type'] == 'Primary'][0]
    assert img_opt_primary['Limit'] == 1, f"Primary image limit should be 1, got {img_opt_primary['Limit']}"
    assert img_opt_primary['MinWidth'] == 300, f"Primary image minWidth should be 300, got {img_opt_primary['MinWidth']}"

    img_opt_backdrop = [io for io in type_opt['ImageOptions'] if io['Type'] == 'Backdrop'][0]
    assert img_opt_backdrop['Limit'] == 3, f"Backdrop image limit should be 3, got {img_opt_backdrop['Limit']}"
    assert img_opt_backdrop['MinWidth'] == 1920, f"Backdrop image minWidth should be 1920, got {img_opt_backdrop['MinWidth']}"

    with subtest("Verify system configuration"):
        print("Querying system configuration...")
        system_config_json = machine.succeed(
            f'curl -f -H {auth_header} {base_url}/System/Configuration'
        )
        system_config = json.loads(system_config_json)

        assert system_config['ServerName'] == 'test-jellyfin-server', \
            f"ServerName should be 'test-jellyfin-server', got {system_config.get('ServerName')}"
        assert system_config['PreferredMetadataLanguage'] == 'de', \
            f"PreferredMetadataLanguage should be 'de', got {system_config.get('PreferredMetadataLanguage')}"
        assert system_config['MetadataCountryCode'] == 'DE', \
            f"MetadataCountryCode should be 'DE', got {system_config.get('MetadataCountryCode')}"
        assert system_config['UICulture'] == 'de-DE', \
            f"UICulture should be 'de-DE', got {system_config.get('UICulture')}"
        assert system_config['LogFileRetentionDays'] == 7, \
            f"LogFileRetentionDays should be 7, got {system_config.get('LogFileRetentionDays')}"
        assert system_config['ActivityLogRetentionDays'] == 60, \
            f"ActivityLogRetentionDays should be 60, got {system_config.get('ActivityLogRetentionDays')}"
        assert system_config['EnableMetrics'] == True, \
            f"EnableMetrics should be True, got {system_config.get('EnableMetrics')}"
        assert system_config['EnableNormalizedItemByNameIds'] == False, \
            f"EnableNormalizedItemByNameIds should be False, got {system_config.get('EnableNormalizedItemByNameIds')}"
        assert system_config['IsPortAuthorized'] == False, \
            f"IsPortAuthorized should be False, got {system_config.get('IsPortAuthorized')}"
        assert system_config['QuickConnectAvailable'] == False, \
            f"QuickConnectAvailable should be False, got {system_config.get('QuickConnectAvailable')}"
        assert system_config['EnableCaseSensitiveItemIds'] == False, \
            f"EnableCaseSensitiveItemIds should be False, got {system_config.get('EnableCaseSensitiveItemIds')}"
        assert system_config['DisableLiveTvChannelUserDataName'] == False, \
            f"DisableLiveTvChannelUserDataName should be False, got {system_config.get('DisableLiveTvChannelUserDataName')}"
        assert set(system_config['SortReplaceCharacters']) == {'-', '_'}, \
            f"SortReplaceCharacters should be ['-', '_'], got {system_config.get('SortReplaceCharacters')}"
        assert set(system_config['SortRemoveCharacters']) == {'!', '?'}, \
            f"SortRemoveCharacters should be ['!', '?'], got {system_config.get('SortRemoveCharacters')}"
        assert set(system_config['SortRemoveWords']) == {'der', 'die', 'das'}, \
            f"SortRemoveWords should be ['der', 'die', 'das'], got {system_config.get('SortRemoveWords')}"
        assert system_config['MinResumePct'] == 10, \
            f"MinResumePct should be 10, got {system_config.get('MinResumePct')}"
        assert system_config['MaxResumePct'] == 85, \
            f"MaxResumePct should be 85, got {system_config.get('MaxResumePct')}"
        assert system_config['MinAudiobookResume'] == 2, \
            f"MinAudiobookResume should be 2, got {system_config.get('MinAudiobookResume')}"
        assert system_config['MaxAudiobookResume'] == 3, \
            f"MaxAudiobookResume should be 3, got {system_config.get('MaxAudiobookResume')}"
        assert system_config['MinResumeDurationSeconds'] == 120, \
            f"MinResumeDurationSeconds should be 120, got {system_config.get('MinResumeDurationSeconds')}"
        assert system_config['InactiveSessionThreshold'] == 15, \
            f"InactiveSessionThreshold should be 15, got {system_config.get('InactiveSessionThreshold')}"
        assert system_config['LibraryMonitorDelay'] == 30, \
            f"LibraryMonitorDelay should be 30, got {system_config.get('LibraryMonitorDelay')}"
        assert system_config['LibraryUpdateDuration'] == 45, \
            f"LibraryUpdateDuration should be 45, got {system_config.get('LibraryUpdateDuration')}"
        assert system_config['CacheSize'] == 500, \
            f"CacheSize should be 500, got {system_config.get('CacheSize')}"
        assert system_config['ImageSavingConvention'] == 'Compatible', \
            f"ImageSavingConvention should be 'Compatible', got {system_config.get('ImageSavingConvention')}"
        assert system_config['ImageExtractionTimeoutMs'] == 5000, \
            f"ImageExtractionTimeoutMs should be 5000, got {system_config.get('ImageExtractionTimeoutMs')}"
        assert system_config['SkipDeserializationForBasicTypes'] == False, \
            f"SkipDeserializationForBasicTypes should be False, got {system_config.get('SkipDeserializationForBasicTypes')}"
        assert system_config['SaveMetadataHidden'] == True, \
            f"SaveMetadataHidden should be True, got {system_config.get('SaveMetadataHidden')}"
        assert system_config['EnableFolderView'] == True, \
            f"EnableFolderView should be True, got {system_config.get('EnableFolderView')}"
        assert system_config['EnableGroupingMoviesIntoCollections'] == True, \
            f"EnableGroupingMoviesIntoCollections should be True, got {system_config.get('EnableGroupingMoviesIntoCollections')}"
        assert system_config['EnableGroupingShowsIntoCollections'] == True, \
            f"EnableGroupingShowsIntoCollections should be True, got {system_config.get('EnableGroupingShowsIntoCollections')}"
        assert system_config['DisplaySpecialsWithinSeasons'] == False, \
            f"DisplaySpecialsWithinSeasons should be False, got {system_config.get('DisplaySpecialsWithinSeasons')}"
        assert system_config['RemoteClientBitrateLimit'] == 8000000, \
            f"RemoteClientBitrateLimit should be 8000000, got {system_config.get('RemoteClientBitrateLimit')}"
        assert system_config['EnableSlowResponseWarning'] == False, \
            f"EnableSlowResponseWarning should be False, got {system_config.get('EnableSlowResponseWarning')}"
        assert system_config['SlowResponseThresholdMs'] == 1000, \
            f"SlowResponseThresholdMs should be 1000, got {system_config.get('SlowResponseThresholdMs')}"
        assert set(system_config['CorsHosts']) == {'localhost', 'test.example.com'}, \
            f"CorsHosts should be ['localhost', 'test.example.com'], got {system_config.get('CorsHosts')}"
        assert system_config['LibraryScanFanoutConcurrency'] == 2, \
            f"LibraryScanFanoutConcurrency should be 2, got {system_config.get('LibraryScanFanoutConcurrency')}"
        assert system_config['LibraryMetadataRefreshConcurrency'] == 4, \
            f"LibraryMetadataRefreshConcurrency should be 4, got {system_config.get('LibraryMetadataRefreshConcurrency')}"
        assert system_config['AllowClientLogUpload'] == False, \
            f"AllowClientLogUpload should be False, got {system_config.get('AllowClientLogUpload')}"
        assert system_config['EnableExternalContentInSuggestions'] == False, \
            f"EnableExternalContentInSuggestions should be False, got {system_config.get('EnableExternalContentInSuggestions')}"
        assert system_config['DummyChapterDuration'] == 10, \
            f"DummyChapterDuration should be 10, got {system_config.get('DummyChapterDuration')}"
        assert system_config['ChapterImageResolution'] == 'P720', \
            f"ChapterImageResolution should be 'P720', got {system_config.get('ChapterImageResolution')}"
        assert system_config['ParallelImageEncodingLimit'] == 3, \
            f"ParallelImageEncodingLimit should be 3, got {system_config.get('ParallelImageEncodingLimit')}"
        assert len(system_config['CastReceiverApplications']) == 1, \
            f"Should have 1 cast receiver application, got {len(system_config.get('CastReceiverApplications', []))}"
        cast_app = system_config['CastReceiverApplications'][0]
        assert cast_app['Id'] == 'CUSTOM123', \
            f"Cast receiver ID should be 'CUSTOM123', got {cast_app.get('Id')}"
        assert cast_app['Name'] == 'Test Receiver', \
            f"Cast receiver Name should be 'Test Receiver', got {cast_app.get('Name')}"
        trickplay = system_config['TrickplayOptions']
        assert trickplay['EnableHwAcceleration'] == True, \
            f"EnableHwAcceleration should be True, got {trickplay.get('EnableHwAcceleration')}"
        assert trickplay['EnableHwEncoding'] == True, \
            f"EnableHwEncoding should be True, got {trickplay.get('EnableHwEncoding')}"
        assert trickplay['EnableKeyFrameOnlyExtraction'] == True, \
            f"EnableKeyFrameOnlyExtraction should be True, got {trickplay.get('EnableKeyFrameOnlyExtraction')}"
        assert trickplay['ScanBehavior'] == 'Blocking', \
            f"ScanBehavior should be 'Blocking', got {trickplay.get('ScanBehavior')}"
        assert trickplay['ProcessPriority'] == 'Normal', \
            f"ProcessPriority should be 'Normal', got {trickplay.get('ProcessPriority')}"
        assert trickplay['Interval'] == 5000, \
            f"Interval should be 5000, got {trickplay.get('Interval')}"
        assert set(trickplay['WidthResolutions']) == {320, 480, 720}, \
            f"WidthResolutions should be [320, 480, 720], got {trickplay.get('WidthResolutions')}"
        assert trickplay['TileWidth'] == 8, \
            f"TileWidth should be 8, got {trickplay.get('TileWidth')}"
        assert trickplay['TileHeight'] == 8, \
            f"TileHeight should be 8, got {trickplay.get('TileHeight')}"
        assert trickplay['Qscale'] == 6, \
            f"Qscale should be 6, got {trickplay.get('Qscale')}"
        assert trickplay['JpegQuality'] == 85, \
            f"JpegQuality should be 85, got {trickplay.get('JpegQuality')}"
        assert trickplay['ProcessThreads'] == 2, \
            f"ProcessThreads should be 2, got {trickplay.get('ProcessThreads')}"
        assert len(system_config['MetadataOptions']) == 1, \
            f"Should have 1 metadata option, got {len(system_config.get('MetadataOptions', []))}"
        metadata_opt = system_config['MetadataOptions'][0]
        assert metadata_opt['ItemType'] == 'Movie', \
            f"ItemType should be 'Movie', got {metadata_opt.get('ItemType')}"
        assert set(metadata_opt['DisabledMetadataSavers']) == {'Nfo'}, \
            f"DisabledMetadataSavers should be ['Nfo'], got {metadata_opt.get('DisabledMetadataSavers')}"
        assert set(metadata_opt['DisabledMetadataFetchers']) == {'TheMovieDb'}, \
            f"DisabledMetadataFetchers should be ['TheMovieDb'], got {metadata_opt.get('DisabledMetadataFetchers')}"
        assert set(metadata_opt['LocalMetadataReaderOrder']) == {'Nfo'}, \
            f"LocalMetadataReaderOrder should be ['Nfo'], got {metadata_opt.get('LocalMetadataReaderOrder')}"
        assert set(metadata_opt['MetadataFetcherOrder']) == {'TheMovieDb'}, \
            f"MetadataFetcherOrder should be ['TheMovieDb'], got {metadata_opt.get('MetadataFetcherOrder')}"
        assert set(metadata_opt['DisabledImageFetchers']) == {'TheMovieDb'}, \
            f"DisabledImageFetchers should be ['TheMovieDb'], got {metadata_opt.get('DisabledImageFetchers')}"
        assert set(metadata_opt['ImageFetcherOrder']) == {'TheMovieDb'}, \
            f"ImageFetcherOrder should be ['TheMovieDb'], got {metadata_opt.get('ImageFetcherOrder')}"
        assert len(system_config['ContentTypes']) == 1, \
            f"Should have 1 content type, got {len(system_config.get('ContentTypes', []))}"
        content_type = system_config['ContentTypes'][0]
        assert content_type['Name'] == 'test', \
            f"ContentType Name should be 'test', got {content_type.get('Name')}"
        assert content_type['Value'] == 'application/test', \
            f"ContentType Value should be 'application/test', got {content_type.get('Value')}"
        assert len(system_config['PathSubstitutions']) == 1, \
            f"Should have 1 path substitution, got {len(system_config.get('PathSubstitutions', []))}"
        path_sub = system_config['PathSubstitutions'][0]
        assert path_sub['From'] == '/old/path', \
            f"PathSubstitution From should be '/old/path', got {path_sub.get('From')}"
        assert path_sub['To'] == '/new/path', \
            f"PathSubstitution To should be '/new/path', got {path_sub.get('To')}"
        assert set(system_config['CodecsUsed']) == {'h264', 'hevc'}, \
            f"CodecsUsed should be ['h264', 'hevc'], got {system_config.get('CodecsUsed')}"
        assert len(system_config['PluginRepositories']) == 1, \
            f"Should have 1 plugin repository, got {len(system_config.get('PluginRepositories', []))}"
        plugin_repo = system_config['PluginRepositories'][0]
        assert plugin_repo['Name'] == 'Test Repo', \
            f"Plugin repo Name should be 'Test Repo', got {plugin_repo.get('Name')}"
        assert plugin_repo['Url'] == 'https://test.example.com/manifest.json', \
            f"Plugin repo Url should be 'https://test.example.com/manifest.json', got {plugin_repo.get('Url')}"
        assert plugin_repo['Enabled'] == True, \
            f"Plugin repo Enabled should be True, got {plugin_repo.get('Enabled')}"
        assert system_config['EnableLegacyAuthorization'] == False, \
            f"EnableLegacyAuthorization should be False, got {system_config.get('EnableLegacyAuthorization')}"

        print("All system configuration assertions passed!")

    with subtest("Verify encoding configuration"):
        print("Querying encoding configuration...")
        encoding_config_json = machine.succeed(
            f'curl -f -H {auth_header} {base_url}/System/Configuration/encoding'
        )
        encoding_config = json.loads(encoding_config_json)

        assert encoding_config['EnableHardwareEncoding'] == False, \
            f"EnableHardwareEncoding should be False, got {encoding_config.get('EnableHardwareEncoding')}"
        assert encoding_config['AllowHevcEncoding'] == True, \
            f"AllowHevcEncoding should be True, got {encoding_config.get('AllowHevcEncoding')}"
        assert encoding_config['AllowAv1Encoding'] == True, \
            f"AllowAv1Encoding should be True, got {encoding_config.get('AllowAv1Encoding')}"
        assert encoding_config['EnableAudioVbr'] == True, \
            f"EnableAudioVbr should be True, got {encoding_config.get('EnableAudioVbr')}"
        assert encoding_config['EnableThrottling'] == True, \
            f"EnableThrottling should be True, got {encoding_config.get('EnableThrottling')}"
        assert encoding_config['EnableSegmentDeletion'] == True, \
            f"EnableSegmentDeletion should be True, got {encoding_config.get('EnableSegmentDeletion')}"
        assert encoding_config['EnableTonemapping'] == True, \
            f"EnableTonemapping should be True, got {encoding_config.get('EnableTonemapping')}"
        assert encoding_config['DeinterlaceDoubleRate'] == True, \
            f"DeinterlaceDoubleRate should be True, got {encoding_config.get('DeinterlaceDoubleRate')}"
        assert encoding_config['EnableDecodingColorDepth10Hevc'] == False, \
            f"EnableDecodingColorDepth10Hevc should be False, got {encoding_config.get('EnableDecodingColorDepth10Hevc')}"
        assert encoding_config['EnableDecodingColorDepth10Vp9'] == False, \
            f"EnableDecodingColorDepth10Vp9 should be False, got {encoding_config.get('EnableDecodingColorDepth10Vp9')}"
        assert encoding_config['EnableSubtitleExtraction'] == False, \
            f"EnableSubtitleExtraction should be False, got {encoding_config.get('EnableSubtitleExtraction')}"

        assert encoding_config['EncodingThreadCount'] == 4, \
            f"EncodingThreadCount should be 4, got {encoding_config.get('EncodingThreadCount')}"
        assert encoding_config['MaxMuxingQueueSize'] == 4096, \
            f"MaxMuxingQueueSize should be 4096, got {encoding_config.get('MaxMuxingQueueSize')}"
        assert encoding_config['ThrottleDelaySeconds'] == 120, \
            f"ThrottleDelaySeconds should be 120, got {encoding_config.get('ThrottleDelaySeconds')}"
        assert encoding_config['SegmentKeepSeconds'] == 600, \
            f"SegmentKeepSeconds should be 600, got {encoding_config.get('SegmentKeepSeconds')}"
        assert encoding_config['H264Crf'] == 20, \
            f"H264Crf should be 20, got {encoding_config.get('H264Crf')}"
        assert encoding_config['H265Crf'] == 25, \
            f"H265Crf should be 25, got {encoding_config.get('H265Crf')}"

        assert encoding_config['DownMixAudioBoost'] == 3, \
            f"DownMixAudioBoost should be 3, got {encoding_config.get('DownMixAudioBoost')}"
        assert encoding_config['TonemappingDesat'] == 0.5, \
            f"TonemappingDesat should be 0.5, got {encoding_config.get('TonemappingDesat')}"
        assert encoding_config['TonemappingPeak'] == 200, \
            f"TonemappingPeak should be 200, got {encoding_config.get('TonemappingPeak')}"
        assert encoding_config['TonemappingParam'] == 1.5, \
            f"TonemappingParam should be 1.5, got {encoding_config.get('TonemappingParam')}"

        assert encoding_config['TranscodingTempPath'] == '/custom/transcode/path', \
            f"TranscodingTempPath should be '/custom/transcode/path', got {encoding_config.get('TranscodingTempPath')}"
        assert encoding_config['VaapiDevice'] == '/dev/dri/renderD129', \
            f"VaapiDevice should be '/dev/dri/renderD129', got {encoding_config.get('VaapiDevice')}"

        assert encoding_config['DownMixStereoAlgorithm'] == 'Rfc7845', \
            f"DownMixStereoAlgorithm should be 'Rfc7845', got {encoding_config.get('DownMixStereoAlgorithm')}"
        assert encoding_config['HardwareAccelerationType'] == 'vaapi', \
            f"HardwareAccelerationType should be 'vaapi', got {encoding_config.get('HardwareAccelerationType')}"
        assert encoding_config['TonemappingAlgorithm'] == 'hable', \
            f"TonemappingAlgorithm should be 'hable', got {encoding_config.get('TonemappingAlgorithm')}"
        assert encoding_config['TonemappingMode'] == 'rgb', \
            f"TonemappingMode should be 'rgb', got {encoding_config.get('TonemappingMode')}"
        assert encoding_config['TonemappingRange'] == 'pc', \
            f"TonemappingRange should be 'pc', got {encoding_config.get('TonemappingRange')}"
        assert encoding_config['EncoderPreset'] == 'placebo', \
            f"EncoderPreset should be 'placebo', got {encoding_config.get('EncoderPreset')}"
        assert encoding_config['DeinterlaceMethod'] == 'bwdif', \
            f"DeinterlaceMethod should be 'bwdif', got {encoding_config.get('DeinterlaceMethod')}"

        assert set(encoding_config['HardwareDecodingCodecs']) == {'h264', 'hevc', 'vp9', 'av1'}, \
            f"HardwareDecodingCodecs should be ['h264', 'hevc', 'vp9', 'av1'], got {encoding_config.get('HardwareDecodingCodecs')}"
        assert set(encoding_config['AllowOnDemandMetadataBasedKeyframeExtractionForExtensions']) == {'mkv', 'mp4'}, \
            f"AllowOnDemandMetadataBasedKeyframeExtractionForExtensions should be ['mkv', 'mp4'], got {encoding_config.get('AllowOnDemandMetadataBasedKeyframeExtractionForExtensions')}"

        print("All encoding configuration assertions passed!")

    with subtest("Verify branding configuration"):
        print("Querying branding configuration...")
        branding_config_json = machine.succeed(
            f'curl -f -H {auth_header} {base_url}/System/Configuration/Branding'
        )
        branding_config = json.loads(branding_config_json)

        expected_css = "body {\n  background-color: #1a1a2e;\n}\n.headerTop {\n  background-color: #16213e;\n}\n"
        assert branding_config['CustomCss'] == expected_css, \
            f"CustomCss mismatch.\nExpected: {repr(expected_css)}\nGot: {repr(branding_config.get('CustomCss'))}"

        expected_disclaimer = "This is a test Jellyfin server.\nPlease use your assigned credentials.\n"
        assert branding_config['LoginDisclaimer'] == expected_disclaimer, \
            f"LoginDisclaimer mismatch.\nExpected: {repr(expected_disclaimer)}\nGot: {repr(branding_config.get('LoginDisclaimer'))}"

        assert branding_config['SplashscreenEnabled'] == True, \
            f"SplashscreenEnabled should be True, got {branding_config.get('SplashscreenEnabled')}"

        print("All branding configuration assertions passed!")
  '';
}
