{
  pkgs,
  lib,
  evalConfig,
  check,
  ...
}:
{
  jellyfin-enabled-folders-defaults =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";

              libraries."Test Movies" = {
                collectionType = "movies";
                paths = [ "/media/movies" ];
              };

              users = {
                admin = {
                  password = "testpassword";
                  policy.isAdministrator = true;
                };

                restricted = {
                  password = "testpassword";
                  mutable = false;
                  policy.enabledFolders = [ "Test Movies" ];
                };

                open = {
                  password = "testpassword";
                };

                override = {
                  password = "testpassword";
                  mutable = false;
                  policy = {
                    enableAllFolders = true;
                    enabledFolders = [ "Test Movies" ];
                  };
                };
              };
            };
          };
        }
      ];
      inherit (config.config.nixflix.jellyfin) users;
      usersService = config.config.systemd.services.jellyfin-users-config;
    in
    pkgs.runCommand "unit-test-jellyfin-enabled-folders-defaults" { } ''
      ${check "enabledFolders turns off enableAllFolders" (!users.restricted.policy.enableAllFolders)}
      ${check "users without enabledFolders keep full access" users.open.policy.enableAllFolders}
      ${check "explicit enableAllFolders wins over the derived default" users.override.policy.enableAllFolders}
      ${check "configured library names reach the users service" (
        lib.hasInfix "Test Movies" usersService.script
      )}
      ${check "resolved ids are written into the policy payload" (
        lib.hasInfix ".EnabledFolders = $enabledFolders" usersService.script
      )}
      ${check "an ineffective restriction is warned about" (
        lib.any (warning: lib.hasInfix "has no effect" warning) config.config.warnings
      )}

      echo 'PASS: jellyfin-enabled-folders-defaults' > $out
    '';

  jellyfin-users-folder-ordering =
    let
      mkUsersService =
        extraPolicy:
        (evalConfig [
          {
            nixflix = {
              enable = true;

              jellyfin = {
                enable = true;
                apiKey = "test-jellyfin-key";

                libraries."Test Movies" = {
                  collectionType = "movies";
                  paths = [ "/media/movies" ];
                };

                users.admin = {
                  password = "testpassword";
                  policy = {
                    isAdministrator = true;
                  }
                  // extraPolicy;
                };
              };
            };
          }
        ]).config.systemd.services.jellyfin-users-config;

      restrictedService = mkUsersService { enabledFolders = [ "Test Movies" ]; };
      openService = mkUsersService { };
    in
    pkgs.runCommand "unit-test-jellyfin-users-folder-ordering" { } ''
      ${check "restricting folders orders users after library creation" (
        builtins.elem "jellyfin-libraries.service" restrictedService.after
      )}
      ${check "library creation is not a hard dependency" (
        !builtins.elem "jellyfin-libraries.service" restrictedService.requires
      )}
      ${check "unrestricted users keep the original ordering" (
        !builtins.elem "jellyfin-libraries.service" openService.after
      )}

      echo 'PASS: jellyfin-users-folder-ordering' > $out
    '';

  jellyfin-enabled-folders-unknown-library-assertion =
    let
      # Asserted on config.assertions directly: system.build.toplevel does not
      # evaluate in this harness, so a tryEval on it would pass for any config.
      # Filtered by message because the bare harness always trips the
      # fileSystems and grub assertions.
      failingAssertions =
        enabledFolders:
        lib.filter (entry: !entry.assertion && lib.hasInfix "enabledFolders" entry.message)
          (evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  apiKey = "test-jellyfin-key";

                  libraries."Test Movies" = {
                    collectionType = "movies";
                    paths = [ "/media/movies" ];
                  };

                  users.admin = {
                    password = "testpassword";
                    policy = {
                      isAdministrator = true;
                      inherit enabledFolders;
                    };
                  };
                };
              };
            }
          ]).config.assertions;

      unknown = failingAssertions [ "Nonexistent" ];
      declared = failingAssertions [ "Test Movies" ];
    in
    pkgs.runCommand "unit-test-jellyfin-enabled-folders-unknown-library-assertion" { } ''
      ${check "an undeclared library name trips exactly one assertion" (lib.length unknown == 1)}
      ${check "the assertion names the bad entry and the configured libraries" (
        lib.hasInfix "users.admin.policy.enabledFolders = \"Nonexistent\"" (lib.head unknown).message
        && lib.hasInfix "Configured libraries: Test Movies" (lib.head unknown).message
      )}
      ${check "a declared library name trips no assertions" (declared == [ ])}

      echo 'PASS: jellyfin-enabled-folders-unknown-library-assertion' > $out
    '';

  jellyfin-integration =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };

            radarr = {
              enable = true;
              mediaDirs = [ "/media/movies" ];
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };

            sonarr = {
              enable = true;
              mediaDirs = [ "/media/shows" ];
              config = {
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/shows"; } ];
              };
            };

            sonarr-anime = {
              enable = true;
              mediaDirs = [ "/media/anime" ];
              config = {
                hostConfig = {
                  port = 8990;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-anime-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-anime-api";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };

            lidarr = {
              enable = true;
              mediaDirs = [ "/media/music" ];
              config = {
                hostConfig = {
                  port = 8686;
                  username = "admin";
                  password._secret = "/run/secrets/lidarr-pass";
                };
                apiKey._secret = "/run/secrets/lidarr-api";
                rootFolders = [ { path = "/media/music"; } ];
              };
            };
          };
        }
      ];

      inherit (config.config.nixflix.jellyfin) libraries;
    in
    pkgs.runCommand "unit-test-jellyfin-integration" { } ''
      ${check "Movies library exists" (libraries ? Movies)}
      ${check "Movies library has correct collectionType" (libraries.Movies.collectionType == "movies")}
      ${check "Movies library has correct path" (builtins.elem "/media/movies" libraries.Movies.paths)}

      ${check "Shows library exists" (libraries ? Shows)}
      ${check "Shows library has correct collectionType" (libraries.Shows.collectionType == "tvshows")}
      ${check "Shows library has correct path" (builtins.elem "/media/shows" libraries.Shows.paths)}

      ${check "Anime library exists" (libraries ? Anime)}
      ${check "Anime library has correct collectionType" (libraries.Anime.collectionType == "tvshows")}
      ${check "Anime library has correct path" (builtins.elem "/media/anime" libraries.Anime.paths)}

      ${check "Music library exists" (libraries ? Music)}
      ${check "Music library has correct collectionType" (libraries.Music.collectionType == "music")}
      ${check "Music library has correct path" (builtins.elem "/media/music" libraries.Music.paths)}

      echo 'PASS: jellyfin-integration' > $out
    '';

  jellyfin-wildcard-bind-connection-address =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
              network.localNetworkAddresses = [ "0.0.0.0" ];
            };
            radarr = {
              enable = true;
              config = {
                hostConfig.port = 7878;
                apiKey._secret = "/run/secrets/radarr-api";
              };
            };
          };
        }
      ];
      jellyfinCfg = config.config.nixflix.jellyfin;
      radarrNotifications = config.config.systemd.services."radarr-notifications";
    in
    pkgs.runCommand "unit-test-jellyfin-wildcard-bind-connection-address" { } ''
      ${check "jellyfin connectionAddress is 127.0.0.1 when bound to 0.0.0.0" (
        jellyfinCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "radarr Jellyfin notification host is not 0.0.0.0" (
        config.config.nixflix.notif.jellyfin.host == "127.0.0.1"
        && !lib.hasInfix "0.0.0.0" radarrNotifications.script
      )}
      echo 'PASS: jellyfin-wildcard-bind-connection-address' > $out
    '';

  jellyfin-subtitles =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-api-key";

              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };

              plugins = {
                "Open Subtitles" = {
                  enable = true;
                  config = {
                    Username = "testsubsuser";
                    Password = "opensubs_test_password";
                  };
                };

                subbuzz = {
                  enable = true;
                  config = {
                    EnableOpenSubtitles = true;
                    EnableYifySubtitles = true;
                    MinScore = 60;
                    Cache.SubLifeInMinutes = "Always";
                    SubPostProcessing.EncodeSubtitlesToUTF8 = false;
                  };
                };

                "Subtitle Extract" = {
                  enable = true;
                  config = {
                    ExtractionDuringLibraryScan = true;
                    IncludeTextSubtitles = true;
                    IncludeGraphicalSubtitles = false;
                  };
                };
              };

              libraries."Subtitle Movies" = {
                collectionType = "movies";
                paths = [ "/media/movies" ];
                subtitleFetcherOrder = [
                  "Open Subtitles"
                  "subbuzz"
                ];
                subtitleDownloadLanguages = [
                  "eng"
                  "spa"
                ];
                saveSubtitlesWithMedia = true;
                allowEmbeddedSubtitles = "AllowAll";
                requirePerfectSubtitleMatch = true;
                skipSubtitlesIfAudioTrackMatches = false;
                skipSubtitlesIfEmbeddedSubtitlesPresent = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
      jellyfinCfg = config.config.nixflix.jellyfin;
    in
    pkgs.runCommand "unit-test-jellyfin-subtitles" { } ''
      ${check "jellyfin-plugins service exists" (config.config.systemd.services ? jellyfin-plugins)}

      ${check "Open Subtitles plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: Open Subtitles" pluginService.script
      )}
      ${check "subbuzz plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: subbuzz" pluginService.script
      )}
      ${check "Subtitle Extract plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: Subtitle Extract" pluginService.script
      )}

      ${check "Open Subtitles plugin directory name in service script" (
        lib.hasInfix "Open-Subtitles-" pluginService.script
      )}
      ${check "subbuzz plugin directory name in service script" (
        lib.hasInfix "subbuzz-" pluginService.script
      )}
      ${check "Subtitle Extract plugin directory name in service script" (
        lib.hasInfix "Subtitle-Extract-" pluginService.script
      )}

      ${check "subbuzz EnableOpenSubtitles config value" jellyfinCfg.plugins.subbuzz.config.EnableOpenSubtitles}
      ${check "subbuzz EnableYifySubtitles config value" jellyfinCfg.plugins.subbuzz.config.EnableYifySubtitles}
      ${check "subbuzz MinScore config value" (jellyfinCfg.plugins.subbuzz.config.MinScore == 60)}
      ${check "subbuzz Cache.SubLifeInMinutes is 1000001 when set to Always" (
        jellyfinCfg.plugins.subbuzz.config.Cache.SubLifeInMinutes == 1000001
      )}
      ${check "subbuzz SubPostProcessing.EncodeSubtitlesToUTF8 config value" (
        !jellyfinCfg.plugins.subbuzz.config.SubPostProcessing.EncodeSubtitlesToUTF8
      )}

      ${check "Open Subtitles Username config value" (
        jellyfinCfg.plugins."Open Subtitles".config.Username == "testsubsuser"
      )}

      ${check "Subtitle Extract ExtractionDuringLibraryScan config value"
        jellyfinCfg.plugins."Subtitle Extract".config.ExtractionDuringLibraryScan
      }
      ${check "Subtitle Extract IncludeTextSubtitles config value"
        jellyfinCfg.plugins."Subtitle Extract".config.IncludeTextSubtitles
      }
      ${check "Subtitle Extract IncludeGraphicalSubtitles config value" (
        !jellyfinCfg.plugins."Subtitle Extract".config.IncludeGraphicalSubtitles
      )}

      ${check "Subtitle Movies library exists" (jellyfinCfg.libraries ? "Subtitle Movies")}
      ${check "Library subtitle fetcher order" (
        jellyfinCfg.libraries."Subtitle Movies".subtitleFetcherOrder == [
          "Open Subtitles"
          "subbuzz"
        ]
      )}
      ${check "Library subtitle download languages" (
        builtins.elem "eng" jellyfinCfg.libraries."Subtitle Movies".subtitleDownloadLanguages
        && builtins.elem "spa" jellyfinCfg.libraries."Subtitle Movies".subtitleDownloadLanguages
      )}
      ${check "Library saveSubtitlesWithMedia"
        jellyfinCfg.libraries."Subtitle Movies".saveSubtitlesWithMedia
      }
      ${check "Library allowEmbeddedSubtitles" (
        jellyfinCfg.libraries."Subtitle Movies".allowEmbeddedSubtitles == "AllowAll"
      )}
      ${check "Library requirePerfectSubtitleMatch"
        jellyfinCfg.libraries."Subtitle Movies".requirePerfectSubtitleMatch
      }
      ${check "Library skipSubtitlesIfEmbeddedSubtitlesPresent"
        jellyfinCfg.libraries."Subtitle Movies".skipSubtitlesIfEmbeddedSubtitlesPresent
      }
      ${check "Library skipSubtitlesIfAudioTrackMatches" (
        !jellyfinCfg.libraries."Subtitle Movies".skipSubtitlesIfAudioTrackMatches
      )}

      echo 'PASS: jellyfin-subtitles' > $out
    '';
}
