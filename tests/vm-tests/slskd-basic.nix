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
  name = "slskd-basic-test";

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
          vpn.enable = false;
          username._secret = pkgs.writeText "slskd-username" "testuser";
          password._secret = pkgs.writeText "slskd-password" "testpassword123";
          apiKey._secret = pkgs.writeText "slskd-apikey" "0123456789abcdef0123456789abcdef";

          settings.soulseek = {
            username._secret = pkgs.writeText "soulseek-username" "soulseekuser";
            password._secret = pkgs.writeText "soulseek-password" "soulseekpassword";
          };
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
    machine.wait_for_unit("slskd-env.service", timeout=60)
    machine.succeed("test -f /run/slskd/env")
    machine.succeed("grep -q SLSKD_USERNAME=testuser /run/slskd/env")
    machine.succeed("grep -q SLSKD_PASSWORD=testpassword123 /run/slskd/env")
    machine.succeed("grep -q SLSKD_API_KEY=0123456789abcdef0123456789abcdef /run/slskd/env")
    machine.succeed("grep -q SLSKD_SLSK_USERNAME=soulseekuser /run/slskd/env")
    machine.succeed("grep -q SLSKD_SLSK_PASSWORD=soulseekpassword /run/slskd/env")

    machine.wait_for_unit("slskd.service", timeout=120)
    machine.wait_for_open_port(5030, timeout=120)
    machine.succeed("curl -fsS http://127.0.0.1:5030/health")

    print("DroppedNeedle and slskd both booted and are wired together!")
  '';
}
