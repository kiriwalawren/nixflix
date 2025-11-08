{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "full-stack-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;

      prowlarr = {
        enable = true;
        config = {
          hostConfig = {
            port = 9696;
            username = "admin";
            passwordPath = "${pkgs.writeText "prowlarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111"}";
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
            passwordPath = "${pkgs.writeText "sonarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222"}";
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
            passwordPath = "${pkgs.writeText "radarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333"}";
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
            passwordPath = "${pkgs.writeText "lidarr-password" "testpass"}";
          };
          apiKeyPath = "${pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444"}";
        };
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for all services to start
    machine.wait_for_unit("prowlarr.service", timeout=60)
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("lidarr.service", timeout=60)

    # Wait for ports
    machine.wait_for_open_port(9696, timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8686, timeout=60)

    # Wait for all configuration services
    machine.wait_for_unit("prowlarr-config.service", timeout=60)
    machine.wait_for_unit("sonarr-config.service", timeout=60)
    machine.wait_for_unit("radarr-config.service", timeout=60)
    machine.wait_for_unit("lidarr-config.service", timeout=60)

    # Wait for all services to come back up after restart
    machine.wait_for_unit("prowlarr.service", timeout=60)
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("lidarr.service", timeout=60)
    machine.wait_for_open_port(9696, timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8686, timeout=60)

    # Test all APIs are accessible
    machine.succeed(
        "curl -f -H 'X-Api-Key: prowlarr11111111111111111111111111' "
        "http://127.0.0.1:9696/api/v1/system/status"
    )
    machine.succeed(
        "curl -f -H 'X-Api-Key: sonarr222222222222222222222222222' "
        "http://127.0.0.1:8989/api/v3/system/status"
    )
    machine.succeed(
        "curl -f -H 'X-Api-Key: radarr333333333333333333333333333' "
        "http://127.0.0.1:7878/api/v3/system/status"
    )
    machine.succeed(
        "curl -f -H 'X-Api-Key: lidarr444444444444444444444444444' "
        "http://127.0.0.1:8686/api/v1/system/status"
    )

    # Wait for additional services (root folders only - indexers omitted)
    machine.wait_for_unit("sonarr-rootfolders.service", timeout=60)
    machine.wait_for_unit("radarr-rootfolders.service", timeout=60)
    machine.wait_for_unit("lidarr-rootfolders.service", timeout=60)
    machine.wait_for_unit("prowlarr-indexers.service", timeout=60)
    machine.wait_for_unit("prowlarr-applications.service", timeout=60)

    # Verify all processes running under correct user
    machine.succeed("pgrep Prowlarr")
    machine.succeed("pgrep -u sonarr Sonarr")
    machine.succeed("pgrep -u radarr Radarr")
    machine.succeed("pgrep -u lidarr dotnet")

    # Test Prowlarr applications were configured
    print("Testing Prowlarr applications configuration...")
    applications = machine.succeed(
        "curl -s -H 'X-Api-Key: prowlarr11111111111111111111111111' "
        "http://127.0.0.1:9696/api/v1/applications"
    )

    # Verify we have 3 applications (Sonarr, Radarr, Lidarr)
    import json
    apps = json.loads(applications)
    assert len(apps) == 3, f"Expected 3 applications, found {len(apps)}"

    # Verify each application type is present
    app_names = {app['name'] for app in apps}
    expected_apps = {'Sonarr', 'Radarr', 'Lidarr'}
    assert app_names == expected_apps, f"Expected {expected_apps}, found {app_names}"

    # Verify implementation names match
    for app in apps:
        assert app['implementationName'] == app['name'], \
            f"Implementation name mismatch for {app['name']}"

    # Verify baseUrl is set correctly for each application
    for app in apps:
        if app['name'] == 'Sonarr':
            expected_url = "http://127.0.0.1:8989"
            actual_url = next(f['value'] for f in app['fields'] if f['name'] == 'baseUrl')
            assert actual_url == expected_url, \
                f"Sonarr baseUrl mismatch: expected {expected_url}, got {actual_url}"
        elif app['name'] == 'Radarr':
            expected_url = "http://127.0.0.1:7878"
            actual_url = next(f['value'] for f in app['fields'] if f['name'] == 'baseUrl')
            assert actual_url == expected_url, \
                f"Radarr baseUrl mismatch: expected {expected_url}, got {actual_url}"
        elif app['name'] == 'Lidarr':
            expected_url = "http://127.0.0.1:8686"
            actual_url = next(f['value'] for f in app['fields'] if f['name'] == 'baseUrl')
            assert actual_url == expected_url, \
                f"Lidarr baseUrl mismatch: expected {expected_url}, got {actual_url}"

    print("Prowlarr applications configuration verified successfully!")
    print("All services are running successfully!")
  '';
}
