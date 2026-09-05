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
  name = "notif-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      virtualisation = {
        cores = 4;
        memorySize = 4096;
        diskSize = 3 * 1024;
      };

      nixflix = {
        enable = true;

        recyclarr.enable = false;

        sonarr = {
          enable = true;
          mediaDirs = [ "/media/tv" ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "0123456789abcdef0123456789abcdef";
          };
        };

        radarr = {
          enable = true;
          mediaDirs = [ "/media/movies" ];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password._secret = pkgs.writeText "radarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";
          };
        };

        lidarr = {
          enable = true;
          mediaDirs = [ "/media/music" ];
          config = {
            hostConfig = {
              port = 8686;
              username = "admin";
              password._secret = pkgs.writeText "lidarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "lidarr-apikey" "5678efgh5678efgh5678efgh5678efgh";
          };
        };

        jellyfin = {
          enable = true;
          apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";

          users.admin = {
            password._secret = pkgs.writeText "jellyfin-admin-password" "321password";
            policy.isAdministrator = true;
          };
        };

        navidrome = {
          enable = true;
          users.admin = {
            userName = "admin";
            isAdmin = true;
            mutable = false;
            password._secret = pkgs.writeText "navidrome-admin-password" "navidromepassword123";
          };
        };
      };

      systemd.services.jellyfin.serviceConfig.TimeoutStartSec = pkgs.lib.mkForce 300;
    };

  testScript = ''
    import json

    start_all()

    SONARR_KEY = "0123456789abcdef0123456789abcdef"
    RADARR_KEY = "abcd1234abcd1234abcd1234abcd1234"
    LIDARR_KEY = "5678efgh5678efgh5678efgh5678efgh"

    machine.wait_for_unit("sonarr.service", timeout=180)
    machine.wait_for_unit("radarr.service", timeout=180)
    machine.wait_for_unit("lidarr.service", timeout=180)
    machine.wait_for_open_port(8989, timeout=180)
    machine.wait_for_open_port(7878, timeout=180)
    machine.wait_for_open_port(8686, timeout=180)

    # Wait for the config services (which restart each Starr app)
    machine.wait_for_unit("sonarr-config.service", timeout=180)
    machine.wait_for_unit("radarr-config.service", timeout=180)
    machine.wait_for_unit("lidarr-config.service", timeout=180)

    # Wait for each Starr app to come back up after restart
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("lidarr.service", timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8686, timeout=60)

    # Notif's reconciliation units require jellyfin.service (all three) and
    # navidrome.service (lidarr only), so systemd itself blocks these on Jellyfin/
    # Navidrome being up - a generous timeout covers Jellyfin's slow first boot.
    machine.wait_for_unit("sonarr-notifications.service", timeout=300)
    machine.wait_for_unit("radarr-notifications.service", timeout=60)
    machine.wait_for_unit("lidarr-notifications.service", timeout=60)

    def get_notifications(port, api_key, api_version="v3"):
        raw = machine.succeed(
            f"curl -sf -H 'X-Api-Key: {api_key}' http://127.0.0.1:{port}/api/{api_version}/notification"
        )
        return json.loads(raw)

    # Sonarr and Radarr should only get the Emby/Jellyfin connection - Subsonic
    # is Lidarr-only and must NOT show up here.
    sonarr_notifs = get_notifications(8989, SONARR_KEY)
    print(f"Sonarr notifications: {sonarr_notifs}")
    assert len(sonarr_notifs) == 1, f"Expected 1 notification on Sonarr, found {len(sonarr_notifs)}"
    assert sonarr_notifs[0]["implementationName"] == "Emby / Jellyfin", \
        f"Expected Emby/Jellyfin, got {sonarr_notifs[0].get('implementationName')}"
    sonarr_host = next(f for f in sonarr_notifs[0]["fields"] if f["name"] == "host")
    assert sonarr_host["value"] == "127.0.0.1", f"Expected host '127.0.0.1', found {sonarr_host['value']}"
    sonarr_port = next(f for f in sonarr_notifs[0]["fields"] if f["name"] == "port")
    assert sonarr_port["value"] == 8096, f"Expected port 8096, found {sonarr_port['value']}"

    radarr_notifs = get_notifications(7878, RADARR_KEY)
    print(f"Radarr notifications: {radarr_notifs}")
    assert len(radarr_notifs) == 1, f"Expected 1 notification on Radarr, found {len(radarr_notifs)}"
    assert radarr_notifs[0]["implementationName"] == "Emby / Jellyfin", \
        f"Expected Emby/Jellyfin, got {radarr_notifs[0].get('implementationName')}"

    # Lidarr should get BOTH Emby/Jellyfin (Music library exists because Lidarr is
    # enabled) and Subsonic (Navidrome is enabled).
    lidarr_notifs = get_notifications(8686, LIDARR_KEY, api_version="v1")
    print(f"Lidarr notifications: {lidarr_notifs}")
    assert len(lidarr_notifs) == 2, \
        f"Expected 2 notifications on Lidarr (Emby/Jellyfin + Subsonic), found {len(lidarr_notifs)}"

    lidarr_media_browser = next(n for n in lidarr_notifs if n["implementationName"] == "Emby / Jellyfin")
    lidarr_subsonic = next(n for n in lidarr_notifs if n["implementationName"] == "Subsonic")

    subsonic_host = next(f for f in lidarr_subsonic["fields"] if f["name"] == "host")
    assert subsonic_host["value"] == "127.0.0.1", f"Expected Subsonic host '127.0.0.1', found {subsonic_host['value']}"
    subsonic_port = next(f for f in lidarr_subsonic["fields"] if f["name"] == "port")
    assert subsonic_port["value"] == 4533, f"Expected Subsonic port 4533, found {subsonic_port['value']}"
    subsonic_username = next(f for f in lidarr_subsonic["fields"] if f["name"] == "username")
    assert subsonic_username["value"] == "admin", \
        f"Expected Subsonic username 'admin', found {subsonic_username['value']}"

    print("Notif configured Emby/Jellyfin on Sonarr/Radarr/Lidarr and Subsonic on Lidarr only!")
  '';
}
