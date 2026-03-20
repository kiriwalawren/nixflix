{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellystat-basic";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ nixosModules ];

      virtualisation = {
        cores = 4;
        memorySize = 4096;
        diskSize = 3 * 1024;
      };

      nixflix = {
        enable = true;

        postgres.enable = true;

        jellyfin = {
          enable = true;

          users = {
            admin = {
              password = {
                _secret = pkgs.writeText "jellyfin_password" "testpass";
              };
              policy.isAdministrator = true;
            };
          };
        };

        jellystat = {
          enable = true;
          jellyfin.apiKey = {
            _secret = pkgs.writeText "jellystat-apikey" "jellyfin_api_key_123456789012";
          };
          jwtSecret = {
            _secret = pkgs.writeText "jellystat-jwt" "super_secret_jwt_key_for_jellystat";
          };
        };
      };

      systemd.services.jellyfin.serviceConfig.TimeoutStartSec = lib.mkForce 300;
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("postgresql.service", timeout=120)
    machine.wait_for_unit("jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=300)
    machine.wait_for_unit("jellystat.service", timeout=300)
    machine.wait_for_open_port(3000, timeout=300)
  '';
}
