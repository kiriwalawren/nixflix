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

  assertTest = name: cond:
    pkgs.runCommand "unit-test-${name}" {} ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  restishConfigTest = import ./restish-config.nix {inherit pkgs lib;};
in {
  restish-config-generation = assertTest "restish-config-generation" restishConfigTest.allPass;
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
                passwordPath = "/run/secrets/sonarr-pass";
              };
              apiKeyPath = "/run/secrets/sonarr-api";
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
                passwordPath = "/run/secrets/radarr-pass";
              };
              apiKeyPath = "/run/secrets/radarr-api";
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
                passwordPath = "/run/secrets/prowlarr-pass";
              };
              apiKeyPath = "/run/secrets/prowlarr-api";
              indexers = [
                {
                  name = "1337x";
                  apiKeyPath = "/run/secrets/1337x-api";
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
            apiKeyPath = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
            nzbKeyPath = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
            environmentSecrets = [
              {
                env = "EWEKA_USERNAME";
                path = pkgs.writeText "eweka-username" "testuser";
              }
              {
                env = "EWEKA_PASSWORD";
                path = pkgs.writeText "eweka-password" "testpass123";
              }
            ];
            settings = {
              port = 8080;
              host = "127.0.0.1";
              url_base = "/sabnzbd";
              ignore_samples = true;
              direct_unpack = false;
              article_tries = 5;
              servers = [
                {
                  name = "TestServer";
                  host = "news.example.com";
                  port = 563;
                  username = "$EWEKA_USERNAME";
                  password = "$EWEKA_PASSWORD";
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
    hasAllServices = systemdUnits ? sabnzbd && systemdUnits ? sabnzbd-config;
  in
    assertTest "prowlarr-service-generation" hasAllServices;
}
