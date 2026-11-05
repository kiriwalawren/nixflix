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
  name = "notif-jellyfin-wildcard-bind-test";

  nodes.machine = { pkgs, ... }: {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 3 * 1024;
    };

    nixflix = {
      enable = true;

      recyclarr.enable = false;

      radarr = {
        enable = true;
        mediaDirs = [ "/media/movies" ];
        config = {
          hostConfig = {
            port = 7878;
            bindAddress = "0.0.0.0";
            username = "admin";
            password._secret = pkgs.writeText "radarr-password" "testpassword123";
          };
          apiKey._secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";
        };
      };

      jellyfin = {
        enable = true;
        network.localNetworkAddresses = [ "0.0.0.0" ];
        apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";

        users.admin = {
          password._secret = pkgs.writeText "jellyfin-admin-password" "321password";
          policy.isAdministrator = true;
        };
      };
    };

    systemd.services.jellyfin.serviceConfig.TimeoutStartSec = pkgs.lib.mkForce 300;
  };

  testScript = ''
    import json

    start_all()

    RADARR_KEY = "abcd1234abcd1234abcd1234abcd1234"

    machine.wait_for_unit("radarr-config.service", timeout=180)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_open_port(7878, timeout=60)

    machine.wait_for_unit("radarr-notifications.service", timeout=300)

    notifs = json.loads(machine.succeed(
        f"curl -sf -H 'X-Api-Key: {RADARR_KEY}' http://127.0.0.1:7878/api/v3/notification"
    ))
    print(f"Radarr notifications: {notifs}")
    assert len(notifs) == 1, f"Expected 1 notification on Radarr, found {len(notifs)}"
    assert notifs[0]["implementationName"] == "Emby / Jellyfin", \
        f"Expected Emby/Jellyfin, got {notifs[0].get('implementationName')}"
    host = next(f for f in notifs[0]["fields"] if f["name"] == "host")
    assert host["value"] == "127.0.0.1", f"Expected host '127.0.0.1', found {host['value']}"

    print("Radarr's Jellyfin notification uses 127.0.0.1 when Jellyfin binds 0.0.0.0")
  '';
}
