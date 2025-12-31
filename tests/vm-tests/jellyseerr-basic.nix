{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}: let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };
in
  pkgsUnfree.testers.runNixOSTest {
    name = "jellyseerr-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        jellyseerr = {
          enable = true;
          port = 5055;
          vpn.enable = false;
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for jellyseerr service
      machine.wait_for_unit("jellyseerr.service", timeout=120)
      machine.wait_for_open_port(5055, timeout=120)

      # Test HTTP connectivity
      machine.succeed(
          "curl -f http://127.0.0.1:5055"
      )

      # Verify the service is running as correct user
      machine.succeed("pgrep -u jellyseerr")

      # Check that data directory exists with correct ownership
      machine.succeed("test -d /data/.state/jellyseerr")

      # Verify directory ownership
      ownership = machine.succeed("stat -c '%U:%G' /data/.state/jellyseerr").strip()
      assert ownership == "jellyseerr:jellyseerr", \
          f"Expected directory owned by jellyseerr:jellyseerr, found {ownership}"

      print("Jellyseerr is running successfully!")
    '';
  }
