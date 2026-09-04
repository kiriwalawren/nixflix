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

        droppedneedle.enable = true;
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

    # DroppedNeedle
    machine.wait_for_unit("droppedneedle.service", timeout=300)
    machine.wait_for_open_port(8688, timeout=300)

    # The upgrade health server listens on this port immediately, reporting
    # {"status": "upgrading"} until the one-time migration finishes and the
    # real target app (target_main:app) takes over - poll until it flips.
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:8688/health | jq -e '.status == \"ok\"'",
        timeout=300,
    )

    # SLSKD_DOWNLOADS_PATH wiring: both services share the same directory
    machine.succeed(
        "test \"$(systemctl show -P Environment droppedneedle.service | tr ' ' '\\n' | grep ^SLSKD_DOWNLOADS_PATH= | cut -d= -f2-)\" = \"/data/downloads/slskd\""
    )

    # config.json persists `port` and normally shadows PORT on every later
    # boot (backend/core/config.py: load_from_file() unconditionally
    # setattr()s it) - corrupt it and confirm the port-sync ExecStartPre
    # restores our declared value before the app starts.
    machine.succeed(
        "jq '.port = 1234' /var/lib/droppedneedle/config/config.json > /tmp/c.json && "
        "mv /tmp/c.json /var/lib/droppedneedle/config/config.json && "
        "chown droppedneedle:media /var/lib/droppedneedle/config/config.json"
    )
    machine.systemctl("restart droppedneedle.service")
    machine.wait_for_open_port(8688, timeout=120)
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:8688/health | jq -e '.status == \"ok\"'",
        timeout=120,
    )
    machine.succeed(
        "jq -e '.port == 8688' /var/lib/droppedneedle/config/config.json"
    )

    print("DroppedNeedle and slskd both booted and are wired together!")
  '';
}
