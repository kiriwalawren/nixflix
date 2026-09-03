{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  inherit (pkgs) lib;
  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };
  secrets = import ../../lib/secrets { inherit lib; };
  manifestHash =
    file:
    builtins.convertHash {
      hash = builtins.hashFile "sha256" file;
      hashAlgo = "sha256";
      toHashFormat = "sri";
    };

  # Helper to evaluate a NixOS configuration without building
  evalConfig =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        {
          # Minimal NixOS config stubs needed for evaluation
          nixpkgs.hostPlatform = system;
        }
      ]
      ++ modules;
    };

  # Test helper to assert conditions
  assertTest =
    name: cond:
    pkgs.runCommand "unit-test-${name}" { } ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  check = name: cond: ''
    ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
    echo 'PASS: ${name}'
  '';
in
{
  # Test that nixflix.sonarr options generate correct systemd units
  sonarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/tv"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr && systemdUnits ? sonarr-config && systemdUnits ? sonarr-rootfolders;
    in
    assertTest "sonarr-service-generation" hasAllServices;

  # Test that nixflix.sonarr-anime options generate correct systemd units
  sonarr-anime-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr-anime = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8990;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr-anime
        && systemdUnits ? sonarr-anime-config
        && systemdUnits ? sonarr-anime-rootfolders;
    in
    assertTest "sonarr-anime-service-generation" hasAllServices;

  # Test that radarr options generate correct systemd units
  radarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              user = "testuser";
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
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? radarr && systemdUnits ? radarr-config && systemdUnits ? radarr-rootfolders;
    in
    assertTest "radarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  prowlarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            prowlarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 9696;
                  username = "admin";
                  password._secret = "/run/secrets/prowlarr-pass";
                };
                apiKey._secret = "/run/secrets/prowlarr-api";
                indexers = [
                  {
                    name = "1337x";
                    apiKey._secret = "/run/secrets/1337x-api";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? prowlarr && systemdUnits ? prowlarr-config && systemdUnits ? prowlarr-indexers;
    in
    assertTest "prowlarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  sabnzbd-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            usenetClients.sabnzbd = {
              enable = true;
              downloadsDir = "/downloads/usenet";
              settings = {
                misc = {
                  api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                  nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                  port = 8080;
                  host = "127.0.0.1";
                  url_base = "/sabnzbd";
                  ignore_samples = true;
                  direct_unpack = false;
                  article_tries = 5;
                };
                servers = [
                  {
                    name = "TestServer";
                    host = "news.example.com";
                    port = 563;
                    username._secret = pkgs.writeText "eweka-username" "testuser";
                    password._secret = pkgs.writeText "eweka-password" "testpass123";
                    connections = 10;
                    ssl = true;
                    priority = 0;
                  }
                ];
                categories = [
                  {
                    name = "tv";
                    dir = "tv";
                    priority = 0;
                    pp = 3;
                    script = "None";
                  }
                  {
                    name = "movies";
                    dir = "movies";
                    priority = 1;
                    pp = 2;
                    script = "None";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices = systemdUnits ? sabnzbd;
    in
    assertTest "sabnzbd-service-generation" hasAllServices;

  # Test that seerr generates services with a remote Jellyfin (no local jellyfin)
  seerr-remote-jellyfin =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            seerr = {
              enable = true;
              apiKey._secret = "/run/secrets/seerr-api";
              jellyfin = {
                adminUsername = "remoteadmin";
                adminPassword = "remotepassword";
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
    in
    assertTest "seerr-remote-jellyfin" (
      systemdUnits ? seerr
      && systemdUnits ? seerr-setup
      && systemdUnits ? seerr-jellyfin
      && systemdUnits ? seerr-libraries
      && systemdUnits ? seerr-user-settings
    );

  jellyfin-plugin-package-service-generation =
    let
      plugin = pkgs.runCommand "test-plugin-1.0.0" { } ''
        mkdir -p "$out"
        touch "$out/TestPlugin.dll"
      '';
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              plugins."Test Plugin".package = plugin;
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      tmpfilesSettings = config.config.systemd.tmpfiles.settings;
      pluginPath = "${config.config.nixflix.jellyfin.dataDir}/plugins";
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-package-service-generation" { } ''
      ${check "plugin service exists" (systemdUnits ? jellyfin-plugins)}
      ${check "plugin tmpfiles directory exists" (
        builtins.hasAttr pluginPath tmpfilesSettings."10-jellyfin"
      )}

      echo 'PASS: jellyfin-plugin-package-service-generation' > $out
    '';

  jellyfin-plugin-source-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  plugins."Broken Plugin" = {
                    package = {
                      version = "1.0.0.0";
                    };
                    config.SomeSetting = true;
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-source-assertion" (!result.success);

  jellyfin-plugin-repo-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              plugins.Bookshelf = {
                package = jellyfinPlugins.fromRepo {
                  version = "13.0.0.0";
                  hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
                };
              };
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-repo-service-generation" { } ''
      ${check "plugin service exists for repo-managed plugin" (
        config.config.systemd.services ? jellyfin-plugins
      )}
      ${check "repo-managed plugins resolve to package sync commands" (
        lib.hasInfix "Syncing packaged plugin: Bookshelf" pluginService.script
      )}
      ${check "resolved plugin directory name appears in service script" (
        lib.hasInfix "Bookshelf_13.0.0.0" pluginService.script
      )}

      echo 'PASS: jellyfin-plugin-repo-service-generation' > $out
    '';

  jellyfin-plugin-repo-ambiguity-assertion =
    let
      targetAbi = "${pkgs.jellyfin.version}.0";
      manifestA = pkgs.writeText "jellyfin-plugin-repo-a.json" (
        builtins.toJSON [
          {
            guid = "11111111-1111-1111-1111-111111111111";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-a.zip";
              }
            ];
          }
        ]
      );
      manifestB = pkgs.writeText "jellyfin-plugin-repo-b.json" (
        builtins.toJSON [
          {
            guid = "22222222-2222-2222-2222-222222222222";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-b.zip";
              }
            ];
          }
        ]
      );
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  apiKey = "test-api-key";
                  system.pluginRepositories = lib.mkForce {
                    "Repo A" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestA}";
                      hash = manifestHash manifestA;
                      enabled = true;
                    };
                    "Repo B" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestB}";
                      hash = manifestHash manifestB;
                      enabled = true;
                    };
                  };
                  plugins."Collision Plugin" = {
                    package = jellyfinPlugins.fromRepo {
                      version = "1.0.0.0";
                      hash = lib.fakeHash;
                    };
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-repo-ambiguity-assertion" (!result.success);

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

  download-clients-no-reverse-proxy =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;

            radarr = {
              enable = true;
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

            usenetClients.sabnzbd = {
              enable = true;
              settings.misc = {
                api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                port = 8080;
                url_base = "/sabnzbd";
              };
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
      sabnzbdCfg = config.config.nixflix.usenetClients.sabnzbd;
      downloadClientsService = config.config.systemd.services."radarr-downloadclients";
    in
    pkgs.runCommand "unit-test-download-clients-no-reverse-proxy" { } ''
      ${check "radarr bindAddress is 0.0.0.0 when nginx is disabled" (
        radarrCfg.config.hostConfig.bindAddress == "0.0.0.0"
      )}
      ${check "radarr connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        radarrCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "sabnzbd connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        sabnzbdCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "radarr-downloadclients ExecStartPre uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients ExecStartPre does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients script uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.script
      )}
      ${check "radarr-downloadclients script does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.script
      )}
      echo 'PASS: download-clients-no-reverse-proxy' > $out
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
        lib.hasInfix "Open Subtitles_24.0.0.0" pluginService.script
      )}
      ${check "subbuzz plugin directory name in service script" (
        lib.hasInfix "subbuzz_1.4.1.0" pluginService.script
      )}
      ${check "Subtitle Extract plugin directory name in service script" (
        lib.hasInfix "Subtitle Extract_7.0.0.0" pluginService.script
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

  # LoadCredential replaces the old -env root service; verify the generated unit
  arr-load-credential =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
              };
            };
          };
        }
      ];
      services = config.config.systemd.services;
      svc = services.sonarr.serviceConfig;
    in
    pkgs.runCommand "unit-test-arr-load-credential" { } ''
      ${check "sonarr-env service no longer exists" (!services ? sonarr-env)}
      ${check "LoadCredential set for secret-ref apiKey" (
        builtins.elem "apiKey:/run/secrets/sonarr-api" svc.LoadCredential
      )}
      ${check "no EnvironmentFile" (!svc ? EnvironmentFile)}
      echo 'PASS: arr-load-credential' > $out
    '';

  # hostConfig assertion: username and password must both be set or both be null
  hostconfig-username-requires-password =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = "admin";
                    # password left at default null
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-username-requires-password" (!result.success);

  hostconfig-password-requires-username =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = null;
                    password._secret = "/run/secrets/sonarr-pass";
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-password-requires-username" (!result.success);

  # lidarr metadata/quality profile assertions: at least one profile must be present
  lidarr-qualityprofiles-empty-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                lidarr = {
                  enable = true;
                  config.qualityProfiles = [ ];
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "lidarr-qualityprofiles-empty-assertion" (!result.success);

  lidarr-metadataprofiles-empty-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                lidarr = {
                  enable = true;
                  config.metadataProfiles = [ ];
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "lidarr-metadataprofiles-empty-assertion" (!result.success);

  # https://github.com/kiriwalawren/nixflix/issues/270
  # settings.auth/settings.server must mirror config.hostConfig so that the
  # environment variables actually reflect what the user configured there.
  hostconfig-drives-settings-auth =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  urlBase = "/radarr";
                  authenticationMethod = "external";
                  authenticationRequired = "disabledForLocalAddresses";
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
      environment = config.config.systemd.services.radarr.environment;
    in
    pkgs.runCommand "unit-test-hostconfig-drives-settings-auth" { } ''
      ${check "settings.auth.method mirrors hostConfig.authenticationMethod" (
        radarrCfg.settings.auth.method == "External"
      )}
      ${check "settings.auth.required mirrors hostConfig.authenticationRequired" (
        radarrCfg.settings.auth.required == "DisabledForLocalAddresses"
      )}
      ${check "settings.server.port mirrors hostConfig.port" (radarrCfg.settings.server.port == 7878)}
      ${check "settings.server.urlBase mirrors hostConfig.urlBase" (
        radarrCfg.settings.server.urlBase == "/radarr"
      )}
      ${check "RADARR__AUTH__METHOD env var reflects hostConfig" (
        environment.RADARR__AUTH__METHOD == "External"
      )}
      ${check "RADARR__AUTH__REQUIRED env var reflects hostConfig" (
        environment.RADARR__AUTH__REQUIRED == "DisabledForLocalAddresses"
      )}
      echo 'PASS: hostconfig-drives-settings-auth' > $out
    '';

  # A user should be able to override settings.auth directly (normal priority,
  # no lib.mkForce needed) since the hostConfig-derived value is only mkDefault.
  settings-auth-overrides-hostconfig =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  authenticationMethod = "forms";
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
              settings.auth.method = "External";
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
    in
    assertTest "settings-auth-overrides-hostconfig" (radarrCfg.settings.auth.method == "External");

  nested-secret-in-list-jq-filter =
    let
      rawConfig = {
        Entries = [
          {
            Name = "first";
            Value._secret = secretFile;
          }
        ];
      };
      secretFile = pkgs.writeText "entry-value" "s3cr3t-value\n";
      plainFile = pkgs.writeText "plain.json" (builtins.toJSON (secrets.stripSecretRefs rawConfig));
      jqSecrets = secrets.mkNestedJqSecretArgs rawConfig;
    in
    pkgs.runCommand "unit-test-nested-secret-in-list-jq-filter"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        merged=$(
          echo '{"Entries":[]}' \
            | jq \
                ${jqSecrets.flagsString} \
                --argjson plain "$(cat ${plainFile})" \
                '. * $plain | ${lib.concatStringsSep " | " jqSecrets.assignments}'
        )

        value=$(echo "$merged" | jq -r '.Entries[0].Value')
        if [ "$value" != "s3cr3t-value" ]; then
          echo "FAIL: expected substituted value, got '$value'" && exit 1
        fi
        echo 'PASS: nested-secret-in-list-jq-filter' > $out
      '';
}
// (
  let
    # Runs the real prestart script against a local file instead of /run/beets,
    # skipping chown/chmod (no "beets" user exists in the build sandbox).
    mkBeetsMergedConfig = preScript: ''
      sed \
        -e '/chown/d' -e '/chmod/d' \
        -e 's#/run/beets/config.yaml#'"$PWD"'/config.yaml#g' \
        "${preScript}" > ./prestart.sh
      chmod +x ./prestart.sh
      bash ./prestart.sh
    '';
  in
  {
    beets-service-generation =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              beets.enable = true;
            };
          }
        ];
        systemdUnits = config.config.systemd.services;
        systemdTimers = config.config.systemd.timers;
      in
      assertTest "beets-service-generation" (
        systemdUnits ? beets && systemdTimers ? beets && config.config.users.users ? beets
      );

    beets-default-no-runtime-merge =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              beets.enable = true;
            };
          }
        ];
        svc = config.config.systemd.services.beets.serviceConfig;
      in
      pkgs.runCommand "unit-test-beets-default-no-runtime-merge" { } ''
        ${check "no ExecStartPre without secrets or a navidrome password" (!(svc ? ExecStartPre))}
        ${check "no ExecStartPost without secrets or a navidrome password" (!(svc ? ExecStartPost))}
        ${check "no RuntimeDirectory without secrets or a navidrome password" (!(svc ? RuntimeDirectory))}
        ${check "ExecStart does not reference /run/beets" (!lib.hasInfix "/run/beets" svc.ExecStart)}
        echo 'PASS: beets-default-no-runtime-merge' > $out
      '';

    beets-secrets-yaml-file-wiring =
      let
        secretsFile = pkgs.writeText "beets-secrets.yaml" ''
          musicbrainz:
            user: mbuser
            pass: mbpass
        '';
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              beets = {
                enable = true;
                secretsYamlFile = secretsFile;
              };
            };
          }
        ];
        svc = config.config.systemd.services.beets.serviceConfig;
        preScript = lib.removePrefix "+" svc.ExecStartPre;
      in
      pkgs.runCommand "unit-test-beets-secrets-yaml-file-wiring" { nativeBuildInputs = [ pkgs.yq-go ]; }
        ''
          ${check "RuntimeDirectory set to beets" (svc.RuntimeDirectory == "beets")}
          ${check "ExecStartPre is root-escalated" (lib.hasPrefix "+" svc.ExecStartPre)}
          ${check "ExecStartPost is root-escalated" (lib.hasPrefix "+" svc.ExecStartPost)}
          ${check "ExecStart reads the runtime-merged config" (
            lib.hasInfix "/run/beets/config.yaml" svc.ExecStart
          )}

          ${mkBeetsMergedConfig preScript}

          mbUser=$(yq eval '.musicbrainz.user' ./config.yaml)
          mbPass=$(yq eval '.musicbrainz.pass' ./config.yaml)
          if [ "$mbUser" != "mbuser" ] || [ "$mbPass" != "mbpass" ]; then
            echo "FAIL: expected secrets file to be merged in, got user='$mbUser' pass='$mbPass'" && exit 1
          fi

          baseDirectory=$(yq eval '.directory' ./config.yaml)
          if [ -z "$baseDirectory" ] || [ "$baseDirectory" = "null" ]; then
            echo "FAIL: base settings were lost during the merge" && exit 1
          fi

          echo 'PASS: beets-secrets-yaml-file-wiring' > $out
        '';

    beets-subsonic-settings-when-navidrome-enabled =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              navidrome = {
                enable = true;
                users.admin = {
                  userName = "navadmin";
                  isAdmin = true;
                };
              };
              beets.enable = true;
            };
          }
        ];
        beetsCfg = config.config.nixflix.beets;
      in
      pkgs.runCommand "unit-test-beets-subsonic-settings-when-navidrome-enabled" { } ''
        ${check "subsonic.user matches navidrome first admin" (
          beetsCfg.settings.subsonic.user == "navadmin"
        )}
        ${check "subsonic.auth is password" (beetsCfg.settings.subsonic.auth == "password")}
        ${check "subsonic.url is set" (lib.hasPrefix "http://" beetsCfg.settings.subsonic.url)}
        ${check "subsonicupdate plugin is included" (
          builtins.elem "subsonicupdate" beetsCfg.settings.plugins
        )}
        echo 'PASS: beets-subsonic-settings-when-navidrome-enabled' > $out
      '';

    beets-subsonic-absent-when-navidrome-disabled =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              beets.enable = true;
            };
          }
        ];
        beetsCfg = config.config.nixflix.beets;
      in
      assertTest "beets-subsonic-absent-when-navidrome-disabled" (
        !(beetsCfg.settings ? subsonic) && !(builtins.elem "subsonicupdate" beetsCfg.settings.plugins)
      );

    # Guards that a navidrome password never lands in cfg.settings, which
    # renders straight to a world-readable Nix store file.
    beets-subsonic-password-never-in-nix-settings =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              navidrome = {
                enable = true;
                users.admin = {
                  userName = "navadmin";
                  isAdmin = true;
                  password = "should-never-reach-the-nix-store";
                };
              };
              beets.enable = true;
            };
          }
        ];
        subsonicSettings = config.config.nixflix.beets.settings.subsonic;
      in
      assertTest "beets-subsonic-password-never-in-nix-settings" (!(subsonicSettings ? pass));

    # Regression test: SUBSONIC_PASS must actually reach yq's subprocess env,
    # not just appear in the script source (a prior bug left it unexported).
    beets-subsonic-password-plain-string-merge =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              navidrome = {
                enable = true;
                users.admin = {
                  userName = "navadmin";
                  isAdmin = true;
                  password = "plaintextpassword123";
                };
              };
              beets.enable = true;
            };
          }
        ];
        svc = config.config.systemd.services.beets.serviceConfig;
        preScript = lib.removePrefix "+" svc.ExecStartPre;
      in
      pkgs.runCommand "unit-test-beets-subsonic-password-plain-string-merge"
        { nativeBuildInputs = [ pkgs.yq-go ]; }
        ''
          ${check "RuntimeDirectory present when navidrome supplies a password" (
            svc.RuntimeDirectory == "beets"
          )}

          ${mkBeetsMergedConfig preScript}

          pass=$(yq eval '.subsonic.pass' ./config.yaml)
          if [ "$pass" != "plaintextpassword123" ]; then
            echo "FAIL: expected subsonic.pass to be 'plaintextpassword123', got '$pass'" && exit 1
          fi
          user=$(yq eval '.subsonic.user' ./config.yaml)
          if [ "$user" != "navadmin" ]; then
            echo "FAIL: expected subsonic.user to still be 'navadmin', got '$user'" && exit 1
          fi

          echo 'PASS: beets-subsonic-password-plain-string-merge' > $out
        '';

    beets-subsonic-password-secret-ref-merge =
      let
        secretFile = pkgs.writeText "navidrome-admin-password" "s3cr3t \"nav\" $pass\n";
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              navidrome = {
                enable = true;
                users.admin = {
                  userName = "navadmin";
                  isAdmin = true;
                  password._secret = secretFile;
                };
              };
              beets.enable = true;
            };
          }
        ];
        svc = config.config.systemd.services.beets.serviceConfig;
        preScript = lib.removePrefix "+" svc.ExecStartPre;
      in
      pkgs.runCommand "unit-test-beets-subsonic-password-secret-ref-merge"
        { nativeBuildInputs = [ pkgs.yq-go ]; }
        ''
          if grep -qF 's3cr3t' "${preScript}"; then
            echo "FAIL: prestart script must never embed the secret plaintext directly" && exit 1
          fi

          ${mkBeetsMergedConfig preScript}

          pass=$(yq eval '.subsonic.pass' ./config.yaml)
          if [ "$pass" != 's3cr3t "nav" $pass' ]; then
            echo "FAIL: expected subsonic.pass read from the secret file, got '$pass'" && exit 1
          fi

          echo 'PASS: beets-subsonic-password-secret-ref-merge' > $out
        '';

    # Confirms secretsYamlFile wins over the navidrome-derived password by
    # actually running the merge, not by inferring it from command order.
    beets-combined-secrets-and-subsonic-password-precedence =
      let
        secretsFile = pkgs.writeText "beets-secrets-combined.yaml" ''
          subsonic:
            pass: from-secrets-file
        '';
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              navidrome = {
                enable = true;
                users.admin = {
                  userName = "navadmin";
                  isAdmin = true;
                  password = "from-navidrome";
                };
              };
              beets = {
                enable = true;
                secretsYamlFile = secretsFile;
              };
            };
          }
        ];
        svc = config.config.systemd.services.beets.serviceConfig;
        preScript = lib.removePrefix "+" svc.ExecStartPre;
      in
      pkgs.runCommand "unit-test-beets-combined-secrets-and-subsonic-password-precedence"
        { nativeBuildInputs = [ pkgs.yq-go ]; }
        ''
          ${mkBeetsMergedConfig preScript}

          pass=$(yq eval '.subsonic.pass' ./config.yaml)
          if [ "$pass" != "from-secrets-file" ]; then
            echo "FAIL: expected secretsYamlFile to win over the navidrome-derived password, got '$pass'" && exit 1
          fi

          echo 'PASS: beets-combined-secrets-and-subsonic-password-precedence' > $out
        '';

    beets-lidarr-move-conflict-assertion =
      let
        result = builtins.tryEval (
          let
            config = evalConfig [
              {
                nixflix = {
                  enable = true;
                  lidarr.enable = true;
                  beets = {
                    enable = true;
                    settings.import.move = true;
                  };
                };
              }
            ];
          in
          config.config.system.build.toplevel.drvPath
        );
      in
      assertTest "beets-lidarr-move-conflict-assertion" (!result.success);

    beets-vpn-enable-requires-global-vpn-assertion =
      let
        result = builtins.tryEval (
          let
            config = evalConfig [
              {
                nixflix = {
                  enable = true;
                  beets = {
                    enable = true;
                    vpn.enable = true;
                  };
                };
              }
            ];
          in
          config.config.system.build.toplevel.drvPath
        );
      in
      assertTest "beets-vpn-enable-requires-global-vpn-assertion" (!result.success);

    beets-vpn-confinement-enabled =
      let
        config = evalConfig [
          {
            nixflix = {
              enable = true;
              vpn.enable = true;
              beets = {
                enable = true;
                vpn.enable = true;
              };
            };
          }
        ];
        vpnConfinement = config.config.systemd.services.beets.vpnConfinement;
      in
      assertTest "beets-vpn-confinement-enabled" (
        vpnConfinement.enable && vpnConfinement.vpnNamespace == "wg"
      );
  }
)
