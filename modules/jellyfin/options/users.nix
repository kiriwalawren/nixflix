{lib, ...}:
with lib; let
  secrets = import ../../lib/secrets {inherit lib;};
  configurationOpts = _: {
    options = {
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

      audioLanguagePreference = mkOption {
        type = with types; nullOr str;
        description = "The audio language preference. Defaults to 'Any Language'";
        default = null;
        example = "eng";
      };

      playDefaultAudioTrack = mkOption {
        type = types.bool;
        example = false;
        default = true;
      };

      subtitleLanguagePreference = mkOption {
        type = with types; nullOr str;
        description = "The subtitle language preference. Defaults to 'Any Language'";
        example = "eng";
        default = null;
      };

      displayMissingEpisodes = mkOption {
        type = types.bool;
        description = "Whether to show missing episodes";
        example = true;
        default = false;
      };

      subtitleMode = mkOption {
        type = types.enum [
          "Default"
          "Always"
          "OnlyForced"
          "None"
          "Smart"
        ];
        description = ''
          Default: The default subtitle playback mode.
          Always: Always show subtitles.
          OnlyForced: Only show forced subtitles.
          None: Don't show subtitles.
          Smart: Only show subtitles when the current audio stream is in a different language.
        '';
        default = "Default";
      };

      displayCollectionsView = mkOption {
        type = types.bool;
        description = "Whether to show the Collections View";
        example = true;
        default = false;
      };

      enableLocalPassword = mkOption {
        type = types.bool;
        example = true;
        default = false;
      };

      hidePlayedInLatest = mkOption {
        type = types.bool;
        description = "Whether to hide already played titles in the 'Latest' section";
        example = false;
        default = true;
      };

      rememberAudioSelections = mkOption {
        type = types.bool;
        example = false;
        default = true;
      };

      rememberSubtitleSelections = mkOption {
        type = types.bool;
        example = false;
        default = true;
      };

      enableNextEpisodeAutoPlay = mkOption {
        type = types.bool;
        description = "Automatically play the next episode";
        example = false;
        default = true;
      };

      castReceiverId = mkOption {
        type = types.str;
        default = "F007D354";
      };
    };
  };
  # See: https://github.com/jellyfin/jellyfin/blob/master/src/Jellyfin.Database/Jellyfin.Database.Implementations/Enums/PermissionKind.cs
  # Defaults: https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Data/UserEntityExtensions.cs#L170
  policyOpts = _: {
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
        type = types.listOf (types.enum [
          "Movie"
          "Trailer"
          "Series"
          "Music"
          "Book"
          "LiveTvChannel"
          "LiveTvProgram"
          "ChannelContent"
          "Other"
        ]);
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
                "Everyday"
                "Weekday"
                "Weekend"
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
        type = types.enum [
          "CreateAndJoinGroups"
          "JoinGroups"
          "None"
        ];
        description = "Whether or not this user has access to SyncPlay";
        example = "None";
        default = "CreateAndJoinGroups";
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

      maxParentalSubRating = mkOption {
        type = with types; nullOr int;
        default = null;
      };

      enableUserPreferenceAccess = mkOption {
        type = types.bool;
        default = true;
      };

      invalidLoginAttemptCount = mkOption {
        type = types.int;
        default = 0;
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

      remoteClientBitrateLimit = mkOption {
        type = types.int;
        description = "0 for unlimited";
        default = 0;
      };
    };
  };
  userOpts = _: {
    options = {
      configuration = mkOption {
        description = "Configuration for this user";
        default = {};
        type = with types; submodule configurationOpts;
        example = {
          subtitleMode = "Always";
          enableNextEpisodeAutoPlay = true;
        };
      };
      policy = mkOption {
        description = "Policy for this user";
        default = {};
        type = with types; submodule policyOpts;
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
      enableAutoLogin = mkOption {
        type = types.bool;
        example = true;
        default = false;
      };
      password = secrets.mkSecretOption {
        default = null;
        description = "User's password.";
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
    description = ''
      User configuration.

      **Important**: At least one user must have `policy.isAdministrator = true`.
      This user will be created during the initial setup wizard and used for
      subsequent API operations.
    '';
    default = {};
    type = with types; attrsOf (submodule userOpts);
    example = {
      admin = {
        password = {_secret = "/run/secrets/jellyfin-admin-password";};
        policy = {
          isAdministrator = true;
        };
      };
    };
  };
}
