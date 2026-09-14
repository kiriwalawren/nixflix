{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };
in
pkgsUnfree.testers.runNixOSTest {
  name = "droppedneedle-slskd-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      virtualisation = {
        diskSize = 4 * 1024;
        memorySize = 4096;
        cores = 4;
      };

      environment.systemPackages = [ pkgs.jq ];

      nixflix = {
        enable = true;

        slskd = {
          enable = true;
          username._secret = pkgs.writeText "slskd-username" "testuser";
          password._secret = pkgs.writeText "slskd-password" "testpassword123";
          apiKey._secret = pkgs.writeText "slskd-apikey" "0123456789abcdef0123456789abcdef";
        };
      };
    };

  testScript = ''
    start_all()

    # Verify tmpfile configuration
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("systemd-tmpfiles-setup.service")
    machine.succeed("systemd-tmpfiles --create --dry-run")

    # slskd: credentials materialized before slskd starts
    machine.wait_for_unit("slskd-secrets.service", timeout=60)
    machine.succeed("test -f /var/lib/slskd/environment")
    machine.succeed("grep -q SLSKD_SLSK_USERNAME=testuser /var/lib/slskd/environment")

    machine.wait_for_unit("slskd.service", timeout=120)
    machine.wait_for_open_port(5030, timeout=120)
    machine.succeed("curl -fsS http://127.0.0.1:5030/health")

    print("DroppedNeedle and slskd both booted and are wired together!")
  '';
}
