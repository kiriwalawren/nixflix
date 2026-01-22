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
  '';
}
