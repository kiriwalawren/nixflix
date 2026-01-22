{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-users";

  nodes.machine = {...}: {
    imports = [nixosModules];

    networking.useDHCP = true;
    virtualisation.diskSize = 3 * 1024;

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
    # Wait for services to start (longer timeout for initial DB migrations and startup)
    machine.wait_for_unit("jellyfin.service", timeout=180)
    machine.wait_for_open_port(port, timeout=180)

    # Wait for configuration services to complete
    machine.wait_for_unit("jellyfin-users-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=180)

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
  '';
}
