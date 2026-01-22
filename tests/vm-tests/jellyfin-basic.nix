{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-basic";

  nodes.machine = {pkgs, ...}: {
    imports = [nixosModules];

    networking.useDHCP = true;
    virtualisation.diskSize = 3 * 1024;

    nixflix = {
      enable = true;

      jellyfin = {
        enable = true;

        users.admin = {
          password = "password123";
          policy.isAdministrator = true;
        };
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for services to start (longer timeout for initial DB migrations and startup)
    machine.wait_for_unit("jellyfin.service", timeout=180)
    machine.wait_for_open_port(8096, timeout=180)

    # Wait for configuration services to complete
    machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=180)
    machine.wait_for_unit("jellyfin-system-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-encoding-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-users-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-branding-config.service", timeout=180)
  '';
}
