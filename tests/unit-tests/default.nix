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
}
