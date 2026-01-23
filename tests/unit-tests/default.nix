{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}: let
  inherit (pkgs) lib;

  # Helper to evaluate a NixOS configuration without building
  evalConfig = modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules =
        [
          nixosModules
          {
            # Minimal NixOS config stubs needed for evaluation
            nixpkgs.hostPlatform = system;
          }
        ]
        ++ modules;
    };

  # Test helper to assert conditions
  assertTest = name: cond:
    pkgs.runCommand "unit-test-${name}" {} ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  check = name: cond: ''
    ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
    echo 'PASS: ${name}'
  '';
in {
  # Test that nixflix.sonarr options generate correct systemd units
  sonarr-service-generation = let
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
                password = {_secret = "/run/secrets/sonarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/sonarr-api";};
              rootFolders = [{path = "/media/tv";}];
            };
          };
        };
      }
    ];
    systemdUnits = config.config.systemd.services;
    hasAllServices = systemdUnits ? sonarr && systemdUnits ? sonarr-config && systemdUnits ? sonarr-rootfolders;
  in
    assertTest "sonarr-service-generation" hasAllServices;

  # Test that nixflix.sonarr-anime options generate correct systemd units
  sonarr-anime-service-generation = let
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
                password = {_secret = "/run/secrets/sonarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/sonarr-api";};
              rootFolders = [{path = "/media/anime";}];
            };
          };
        };
      }
    ];
    systemdUnits = config.config.systemd.services;
    hasAllServices = systemdUnits ? sonarr-anime && systemdUnits ? sonarr-anime-config && systemdUnits ? sonarr-anime-rootfolders;
  in
    assertTest "sonarr-anime-service-generation" hasAllServices;

  # Test that radarr options generate correct systemd units
  radarr-service-generation = let
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
                password = {_secret = "/run/secrets/radarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/radarr-api";};
              rootFolders = [{path = "/media/movies";}];
            };
          };
        };
      }
    ];
    systemdUnits = config.config.systemd.services;
    hasAllServices = systemdUnits ? radarr && systemdUnits ? radarr-config && systemdUnits ? radarr-rootfolders;
  in
    assertTest "radarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  prowlarr-service-generation = let
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
                password = {_secret = "/run/secrets/prowlarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/prowlarr-api";};
              indexers = [
                {
                  name = "1337x";
                  apiKey = {_secret = "/run/secrets/1337x-api";};
                }
              ];
            };
          };
        };
      }
    ];
    systemdUnits = config.config.systemd.services;
    hasAllServices = systemdUnits ? prowlarr && systemdUnits ? prowlarr-config && systemdUnits ? prowlarr-indexers;
  in
    assertTest "prowlarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  sabnzbd-service-generation = let
    config = evalConfig [
      {
        nixflix = {
          enable = true;
          sabnzbd = {
            enable = true;
            downloadsDir = "/downloads/usenet";
            settings = {
              misc = {
                api_key = {_secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";};
                nzb_key = {_secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";};
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
                  username = {_secret = pkgs.writeText "eweka-username" "testuser";};
                  password = {_secret = pkgs.writeText "eweka-password" "testpass123";};
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

  jellyfin-integration = let
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
            mediaDirs = ["/media/movies"];
            config = {
              hostConfig = {
                port = 7878;
                username = "admin";
                password = {_secret = "/run/secrets/radarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/radarr-api";};
              rootFolders = [{path = "/media/movies";}];
            };
          };

          sonarr = {
            enable = true;
            mediaDirs = ["/media/shows"];
            config = {
              hostConfig = {
                port = 8989;
                username = "admin";
                password = {_secret = "/run/secrets/sonarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/sonarr-api";};
              rootFolders = [{path = "/media/shows";}];
            };
          };

          sonarr-anime = {
            enable = true;
            mediaDirs = ["/media/anime"];
            config = {
              hostConfig = {
                port = 8990;
                username = "admin";
                password = {_secret = "/run/secrets/sonarr-anime-pass";};
              };
              apiKey = {_secret = "/run/secrets/sonarr-anime-api";};
              rootFolders = [{path = "/media/anime";}];
            };
          };

          lidarr = {
            enable = true;
            mediaDirs = ["/media/music"];
            config = {
              hostConfig = {
                port = 8686;
                username = "admin";
                password = {_secret = "/run/secrets/lidarr-pass";};
              };
              apiKey = {_secret = "/run/secrets/lidarr-api";};
              rootFolders = [{path = "/media/music";}];
            };
          };
        };
      }
    ];

    inherit (config.config.nixflix.jellyfin) libraries;
  in
    pkgs.runCommand "unit-test-jellyfin-integration" {} ''
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
