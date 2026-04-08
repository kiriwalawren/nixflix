{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  inherit (pkgs) lib;
  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };
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
                  version = "latest";
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

  jellyfin-plugin-repo-ambiguity-warning =
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
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-api-key";
              system.pluginRepositories = lib.mkForce [
                {
                  name = "Repo A";
                  url = builtins.unsafeDiscardStringContext "file://${manifestA}";
                  hash = manifestHash manifestA;
                  enabled = true;
                }
                {
                  name = "Repo B";
                  url = builtins.unsafeDiscardStringContext "file://${manifestB}";
                  hash = manifestHash manifestB;
                  enabled = true;
                }
              ];
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
      pluginService = config.config.systemd.services.jellyfin-plugins;
      inherit (config.config) warnings;
      warningText = builtins.concatStringsSep "\n" warnings;
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-repo-ambiguity-warning" { } ''
      ${check "ambiguity warning emitted" (warnings != [ ])}
      ${check "warning mentions first repo" (lib.hasInfix "Repo A" warningText)}
      ${check "warning mentions second repo" (lib.hasInfix "Repo B" warningText)}
      ${check "warning explains selection" (
        lib.hasInfix "selecting the first repository in configured order" warningText
      )}
      ${check "plugin dir uses plugin identity" (
        lib.hasInfix "Collision-Plugin_1.0.0.0" pluginService.script
      )}

      echo 'PASS: jellyfin-plugin-repo-ambiguity-warning' > $out
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
}
