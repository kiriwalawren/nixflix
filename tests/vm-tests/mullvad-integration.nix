{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "mullvad-integration-test";

  nodes.machine = {pkgs, ...}: {
    imports = [nixosModules];

    nixflix = {
      enable = true;
      mullvad = {
        enable = true;
        autoConnect = false; # Don't auto-connect in tests
        killSwitch = {
          enable = true;
          allowLan = true;
        };
        dns = ["1.1.1.1" "1.0.0.1"];
      };

      prowlarr = {
        enable = true;
        config = {
          hostConfig = {
            port = 9696;
            username = "admin";
            password = {_secret = pkgs.writeText "prowlarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111";};
        };
      };

      sonarr = {
        enable = true;
        user = "sonarr";
        mediaDirs = ["/media/tv"];
        config = {
          hostConfig = {
            port = 8989;
            username = "admin";
            password = {_secret = pkgs.writeText "sonarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";};
        };
      };

      radarr = {
        enable = true;
        user = "radarr";
        mediaDirs = ["/media/movies"];
        config = {
          hostConfig = {
            port = 7878;
            username = "admin";
            password = {_secret = pkgs.writeText "radarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";};
        };
      };

      lidarr = {
        enable = true;
        user = "lidarr";
        mediaDirs = ["/media/music"];
        config = {
          hostConfig = {
            port = 8686;
            username = "admin";
            password = {_secret = pkgs.writeText "lidarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444";};
        };
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for Mullvad daemon to start
    machine.wait_for_unit("mullvad-daemon.service", timeout=60)

    # Wait for Mullvad configuration service
    machine.wait_for_unit("mullvad-config.service", timeout=60)

    # Verify Mullvad daemon is running
    print("Checking Mullvad daemon status...")
    machine.succeed("mullvad status")

    # Verify lockdown mode (kill switch) is enabled
    print("Verifying kill switch is enabled...")
    status = machine.succeed("mullvad lockdown-mode get")
    assert "on" in status.lower(), f"Kill switch not enabled: {status}"

    # Verify LAN access is allowed
    print("Verifying LAN access is allowed...")
    lan_status = machine.succeed("mullvad lan get")
    assert "allow" in lan_status.lower(), f"LAN access not allowed: {lan_status}"

    # Verify DNS settings
    print("Verifying DNS settings...")
    dns_status = machine.succeed("mullvad dns get")
    assert "custom" in dns_status.lower(), f"Custom DNS not configured: {dns_status}"
    assert "1.1.1.1" in dns_status, f"DNS 1.1.1.1 not found in configuration: {dns_status}"
    assert "1.0.0.1" in dns_status, f"DNS 1.0.0.1 not found in configuration: {dns_status}"

    # Verify auto-connect is off (as configured)
    print("Verifying auto-connect is disabled...")
    autoconnect_status = machine.succeed("mullvad auto-connect get")
    assert "off" in autoconnect_status.lower(), f"Auto-connect not disabled: {autoconnect_status}"

    # Test that we can disconnect (service should handle this gracefully even when not connected)
    print("Testing disconnect command...")
    machine.succeed("mullvad disconnect || true")

    # Wait for all services to start
    machine.wait_for_unit("prowlarr.service", timeout=120)
    machine.wait_for_unit("sonarr.service", timeout=120)
    machine.wait_for_unit("radarr.service", timeout=120)
    machine.wait_for_unit("lidarr.service", timeout=120)

    # Wait for all config services
    machine.wait_for_unit("prowlarr-config.service", timeout=60)
    machine.wait_for_unit("sonarr-config.service", timeout=60)
    machine.wait_for_unit("radarr-config.service", timeout=60)
    machine.wait_for_unit("lidarr-config.service", timeout=60)

    # Verify services are actually running and stable (not crash-looping)
    print("Verifying services are stable and responding...")
    import time
    time.sleep(5)  # Wait for any crashes to happen

    # Wait for all services to start
    machine.wait_for_unit("prowlarr.service", timeout=20)
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_unit("lidarr.service", timeout=20)

    # Check that services are still active (not failed)
    machine.succeed("systemctl is-active prowlarr.service")
    machine.succeed("systemctl is-active sonarr.service")
    machine.succeed("systemctl is-active radarr.service")
    machine.succeed("systemctl is-active lidarr.service")

    # Check that services haven't restarted (restart counter should be 0)
    prowlarr_restarts = machine.succeed("systemctl show prowlarr.service -p NRestarts --value")
    assert prowlarr_restarts.strip() == "0", f"Prowlarr has restarted {prowlarr_restarts.strip()} times"

    sonarr_restarts = machine.succeed("systemctl show sonarr.service -p NRestarts --value")
    assert sonarr_restarts.strip() == "0", f"Sonarr has restarted {sonarr_restarts.strip()} times"

    radarr_restarts = machine.succeed("systemctl show radarr.service -p NRestarts --value")
    assert radarr_restarts.strip() == "0", f"Radarr has restarted {radarr_restarts.strip()} times"

    lidarr_restarts = machine.succeed("systemctl show lidarr.service -p NRestarts --value")
    assert lidarr_restarts.strip() == "0", f"Lidarr has restarted {lidarr_restarts.strip()} times"

    # Verify HTTP endpoints are responding
    machine.wait_for_open_port(9696, timeout=60)  # Prowlarr
    machine.wait_for_open_port(8989, timeout=60)  # Sonarr
    machine.wait_for_open_port(7878, timeout=60)  # Radarr
    machine.wait_for_open_port(8686, timeout=60)  # Lidarr

    print("Mullvad integration test successful! Kill switch configured correctly.")
  '';
}
