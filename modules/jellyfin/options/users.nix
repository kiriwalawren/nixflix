{lib, ...}:
with lib; let
  preferenceOpts = _: {
    options = {
      enabledLibraries = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          A list of libraries this user as access to.
          If it is empty, it means that the user has access to all libraries.
          The libraries are specified by the library name specified in
          `nixflix.jellyfin.libraries.<name>`
        '';
        example = [
          "Movies"
          "Family Photos"
        ];
      };

      groupedFolders = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      orderedViews = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      latestItemsExcludes = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      myMediaExcludes = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };
  # See: https://github.com/jellyfin/jellyfin/blob/master/src/Jellyfin.Database/Jellyfin.Database.Implementations/Enums/PermissionKind.cs
  # Defaults: https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Data/UserEntityExtensions.cs#L170
  permissionOpts = _: {
    options = {
      isAdministrator = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user is an administrator";
      };
      isHidden = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user is hidden";
      };
      isDisabled = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user is disabled";
      };
      enableAllChannels = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user has access to all channels";
      };
      enableAllDevices = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user has access to all devices";
      };
      enableAllFolders = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user has access to all folders";
      };
      enableAudioPlaybackTranscoding = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the server should transcode audio for the user if requested";
      };
      enableCollectionManagement = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user can create, modify and delete collections";
      };
      enableContentDeletion = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user can delete content";
      };
      enableContentDownloading = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can download content";
      };
      enableLiveTvAccess = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can access live tv";
      };
      enableLiveTvManagement = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can manage live tv";
      };
      enableLyricManagement = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user can edit lyrics";
      };
      enableMediaConversion = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can do media conversion";
      };
      enableMediaPlayback = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can play media";
      };
      enablePlaybackRemuxing = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user is permitted to do playback remuxing";
      };
      enablePublicSharing = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable public sharing for the user";
      };
      enableRemoteAccess = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can access the server remotely";
      };
      enableRemoteControlOfOtherUsers = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user can remotely control other users";
      };
      enableSharedDeviceControl = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the user can control shared devices";
      };
      enableSubtitleManagement = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the user can edit subtitles";
      };
      enableSyncTranscoding = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable sync transcoding for the user";
      };
      enableVideoPlaybackTranscoding = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the server should transcode video for the user if requested";
      };
      forceRemoteSourceTranscoding = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the server should force transcoding on remote connections for the user";
      };

      maxParentalRating = mkOption {
        type = types.nullOr types.int;
        default = null;
      };

      blockedTags = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      allowedTags = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      blockUnratedItems = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      enabledDevices = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      enabledChannels = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      blockedMediaFolders = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      blockedChannels = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      enableContentDeletionFromFolders = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      accessSchedules = mkOption {
        type = types.listOf (types.submodule {
          options = {
            dayOfWeek = mkOption {
              type = types.enum [
                "Sunday"
                "Monday"
                "Tuesday"
                "Wednesday"
                "Thursday"
                "Friday"
                "Saturday"
              ];
            };
            startHour = mkOption {
              type = types.ints.between 0 23;
            };
            endHour = mkOption {
              type = types.ints.between 0 23;
            };
          };
        });
        default = [];
      };

      syncPlayAccess = mkOption {
        type = types.bool;
        description = "Whether or not this user has access to SyncPlay";
        example = true;
        default = false;
      };

      authenticationProviderId = mkOption {
        type = types.str;
        default = "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider";
        description = "Authentication provider ID";
      };

      passwordResetProviderId = mkOption {
        type = types.str;
        default = "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider";
        description = "Password reset provider ID";
      };
    };
  };
  userOpts = _: {
    options = {
      preferences = mkOption {
        description = "Preferences for this user";
        default = {};
        type = with types; submodule preferenceOpts;
        example = {
          # Whitelist libraries
          enabledLibraries = [
            "TV Shows"
            "Movies"
          ];
        };
      };
      policy = mkOption {
        description = "Policy for this user";
        default = {};
        type = with types; submodule permissionOpts;
        example = {
          isAdministrator = true;
          enableContentDeletion = false;
          enableSubtitleManagement = true;
          isDisabled = false;
        };
      };
      mutable = mkOption {
        type = types.bool;
        example = false;
        description = ''
          Functions like mutableUsers in NixOS users.users."user"
          If true, the first time the user is created, all configured options
          are overwritten. Any modifications from the GUI will take priority,
          and no nix configuration changes will have any effect.
          If false however, all options are overwritten as specified in the nix configuration,
          which means any change through the Jellyfin GUI will have no effect after a rebuild.

          Note: Passwords are only set during user creation and are never updated
          declaratively, regardless of the mutable setting. To change a user's password,
          use the Jellyfin web interface.
        '';
        default = true;
      };
      id = mkOption {
        type = types.nullOr types.str; # TODO: Limit the id to the pattern: "18B51E25-33FD-46B6-BBF8-DB4DD77D0679"
        description = "The ID of the user";
        example = "18B51E25-33FD-46B6-BBF8-DB4DD77D0679";
        default = null;
      };
      audioLanguagePreference = mkOption {
        type = with types; nullOr str;
        description = "The audio language preference. Defaults to 'Any Language'";
        default = null;
        example = "eng";
      };
      authenticationProviderId = mkOption {
        type = types.str;
        default = "Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider";
      };
      displayCollectionsView = mkOption {
        type = types.bool;
        description = "Whether to show the Collections View";
        example = true;
        default = false;
      };
      displayMissingEpisodes = mkOption {
        type = types.bool;
        description = "Whether to show missing episodes";
        example = true;
        default = false;
      };
      enableAutoLogin = mkOption {
        type = types.bool;
        example = true;
        default = false;
      };
      enableLocalPassword = mkOption {
        type = types.bool;
        example = true;
        default = false;
      };
      enableNextEpisodeAutoPlay = mkOption {
        type = types.bool;
        description = "Automatically play the next episode";
        example = false;
        default = true;
      };
      enableUserPreferenceAccess = mkOption {
        type = types.bool;
        example = false;
        default = true;
      };
      hidePlayedInLatest = mkOption {
        type = types.bool;
        description = "Whether to hide already played titles in the 'Latest' section";
        example = false;
        default = true;
      };
      internalId = mkOption {
        type = with types; nullOr int;
        # NOTE: index is 1-indexed! NOT 0-indexed.
        description = "The index of the user in the database. Be careful setting this option. 1 indexed.";
        example = 69;
        default = null;
      };
      loginAttemptsBeforeLockout = mkOption {
        type = types.nullOr types.int;
        description = "The number of login attempts the user can make before they are locked out. 0 for default (3 for normal users, 5 for admins). null for unlimited";
        example = 10;
        default = 3;
      };
      maxActiveSessions = mkOption {
        type = types.int;
        description = "The maximum number of active sessions the user can have at once. 0 for unlimited";
        example = 5;
        default = 0;
      };
      maxParentalRatingSubScore = mkOption {
        type = with types; nullOr int;
        default = null;
      };
      passwordFile = mkOption {
        type = types.nullOr types.path;
        description = ''
          Path to a file containing the user's password in plain text.
        '';
        default = null;
      };
      passwordResetProviderId = mkOption {
        type = types.str;
        default = "Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider";
      };
      playDefaultAudioTrack = mkOption {
        type = types.bool;
        example = false;
        default = true;
      };
      rememberAudioSelections = mkOption {
        type = types.bool;
        default = true;
      };
      rememberSubtitleSelections = mkOption {
        type = types.bool;
        default = true;
      };
      remoteClientBitrateLimit = mkOption {
        type = types.int;
        description = "0 for unlimited";
        default = 0;
      };
      subtitleLanguagePreference = mkOption {
        type = with types; nullOr str;
        description = "The subtitle language preference. Defaults to 'Any Language'";
        example = "eng";
        default = null;
      };
      # https://github.com/jellyfin/jellyfin/blob/master/src/Jellyfin.Database/Jellyfin.Database.Implementations/Enums/SubtitlePlaybackMode.cs
      subtitleMode = mkOption {
        type = types.enum [
          "default"
          "always"
          "onlyForced"
          "none"
          "smart"
        ];
        description = ''
          Default: The default subtitle playback mode.
          Always: Always show subtitles.
          OnlyForced: Only show forced subtitles.
          None: Don't show subtitles.
          Smart: Only show subtitles when the current audio stream is in a different language.
        '';
        default = "default";
      };
      castReceiverId = mkOption {
        type = types.str;
        default = "F007D354";
      };
      invalidLoginAttemptCount = mkOption {
        type = types.int;
        default = 0;
      };
      mustUpdatePassword = mkOption {
        type = types.int;
        default = 0;
      };
      rowVersion = mkOption {
        type = types.int;
        default = 0;
      };
      lastActivityDate = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      lastLoginDate = mkOption {
        type = with types; nullOr str;
        default = null;
      };
    };
  };
in {
  # Based on: https://github.com/jellyfin/jellyfin/blob/master/MediaBrowser.Model/Configuration/UserConfiguration.cs
  options.nixflix.jellyfin.users = mkOption {
    description = "User configuration";
    default = {};
    type = with types; attrsOf (submodule userOpts);
    example = {
      Admin = {
        password = "123";
        maxParentalRatingSubScore = 12;
        permissions = {
          isAdministrator = true;
        };
      };
    };
  };
}
