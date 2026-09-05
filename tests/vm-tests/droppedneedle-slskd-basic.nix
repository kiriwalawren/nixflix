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

        droppedneedle = {
          enable = true;
          settings.users = {
            admin = {
              userName = "admin";
              email = "admin@example.com";
              role = "admin";
              mutable = false;
              password._secret = pkgs.writeText "droppedneedle-admin-password" "testpassword123456";
            };
            viewer = {
              userName = "viewer";
              role = "user";
              mutable = false;
              password._secret = pkgs.writeText "droppedneedle-viewer-password" "viewerpassword123456";
              quota.requestCount = 10;
              quota.requestDays = 30;
            };
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

    # First-admin creation (setupService.nix) and declarative user config
    # (users/default.nix) both run as oneshots chained off droppedneedle.service.
    machine.wait_for_unit("droppedneedle-create-admin.service", timeout=60)
    machine.wait_for_unit("droppedneedle-users-config.service", timeout=60)

    machine.succeed(
        "curl -fsS -X POST -H 'Content-Type: application/json' "
        "-d '{\"username\":\"admin\",\"password\":\"testpassword123456\"}' "
        "http://127.0.0.1:8688/api/v1/auth/login "
        "| jq -e '.user.username == \"admin\" and .user.role == \"admin\"'"
    )

    machine.succeed(
        "TOKEN=$(curl -fsS -X POST -H 'Content-Type: application/json' "
        "-d '{\"username\":\"admin\",\"password\":\"testpassword123456\"}' "
        "http://127.0.0.1:8688/api/v1/auth/login | jq -r .token); "
        "USERS=$(curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users); "
        "echo \"$USERS\" | jq -e '([.users[].username] | sort) == [\"admin\",\"viewer\"]'; "
        "echo \"$USERS\" | jq -e '.users[] | select(.username==\"viewer\") | .role == \"user\"'; "
        "VIEWER_ID=$(echo \"$USERS\" | jq -r '.users[] | select(.username==\"viewer\") | .id'); "
        "curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users/$VIEWER_ID/quota "
        "| jq -e '.override.request_quota_count == 10 and .override.request_quota_days == 30 and .override.storage_quota_gb == null'"
    )

    # mutable = false: a change made through the API (standing in for the web
    # UI, since there's no admin endpoint to update anything else about a
    # user) must be reverted the next time droppedneedle-users-config runs.
    machine.succeed(
        "TOKEN=$(curl -fsS -X POST -H 'Content-Type: application/json' "
        "-d '{\"username\":\"admin\",\"password\":\"testpassword123456\"}' "
        "http://127.0.0.1:8688/api/v1/auth/login | jq -r .token); "
        "VIEWER_ID=$(curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users | jq -r '.users[] | select(.username==\"viewer\") | .id'); "
        "curl -fsS -X PATCH -H \"Authorization: Bearer $TOKEN\" -H 'Content-Type: application/json' "
        "-d '{\"role\":\"trusted\"}' "
        "http://127.0.0.1:8688/api/v1/auth/admin/users/$VIEWER_ID/role; "
        "curl -fsS -X PUT -H \"Authorization: Bearer $TOKEN\" -H 'Content-Type: application/json' "
        "-d '{\"request_quota_count\":999,\"request_quota_days\":999,\"storage_quota_gb\":999}' "
        "http://127.0.0.1:8688/api/v1/auth/admin/users/$VIEWER_ID/quota"
    )

    machine.systemctl("restart droppedneedle-users-config.service")
    machine.wait_for_unit("droppedneedle-users-config.service", timeout=60)

    machine.succeed(
        "TOKEN=$(curl -fsS -X POST -H 'Content-Type: application/json' "
        "-d '{\"username\":\"admin\",\"password\":\"testpassword123456\"}' "
        "http://127.0.0.1:8688/api/v1/auth/login | jq -r .token); "
        "VIEWER_ID=$(curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users | jq -r '.users[] | select(.username==\"viewer\") | .id'); "
        "curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users | jq -e '.users[] | select(.username==\"viewer\") | .role == \"user\"'; "
        "curl -fsS -H \"Authorization: Bearer $TOKEN\" "
        "http://127.0.0.1:8688/api/v1/auth/admin/users/$VIEWER_ID/quota "
        "| jq -e '.override.request_quota_count == 10 and .override.request_quota_days == 30'"
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
