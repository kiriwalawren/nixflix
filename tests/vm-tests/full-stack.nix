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
    name = "full-stack-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      virtualisation.cores = 4;

      nixflix = {
        enable = true;

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

        sonarr-anime = {
          enable = true;
          user = "sonarr-anime";
          mediaDirs = ["/media/tv"];
          config = {
            hostConfig = {
              port = 8990;
              username = "admin";
              password = {_secret = pkgs.writeText "sonarr-anime-password" "testpass";};
            };
            apiKey = {_secret = pkgs.writeText "sonarr-anime-apikey" "sonarr222222222222222222222222222";};
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

        sabnzbd = {
          enable = true;
          settings = {
            misc = {
              api_key = {_secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";};
              nzb_key = {_secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbdnzb666666666666666666666";};
              port = 8080;
              host = "127.0.0.1";
              url_base = "/sabnzbd";
            };
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Verify tmpfile configuration
      machine.wait_for_unit("multi-user.target")
      machine.succeed("systemd-tmpfiles --create --dry-run")

      # Wait for all services to start (longer timeout for initial DB migrations)
      machine.wait_for_unit("prowlarr.service", timeout=180)
      machine.wait_for_unit("sonarr.service", timeout=180)
      machine.wait_for_unit("sonarr-anime.service", timeout=180)
      machine.wait_for_unit("radarr.service", timeout=180)
      machine.wait_for_unit("lidarr.service", timeout=180)
      machine.wait_for_unit("sabnzbd.service", timeout=60)

      # Wait for ports
      machine.wait_for_open_port(9696, timeout=180)
      machine.wait_for_open_port(8989, timeout=180)
      machine.wait_for_open_port(8990, timeout=180)
      machine.wait_for_open_port(7878, timeout=180)
      machine.wait_for_open_port(8686, timeout=180)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for all configuration services
      machine.wait_for_unit("prowlarr-config.service", timeout=60)
      machine.wait_for_unit("sonarr-config.service", timeout=60)
      machine.wait_for_unit("sonarr-anime-config.service", timeout=60)
      machine.wait_for_unit("radarr-config.service", timeout=60)
      machine.wait_for_unit("lidarr-config.service", timeout=60)

      # Wait for all services to come back up after restart
      machine.wait_for_unit("prowlarr.service", timeout=60)
      machine.wait_for_unit("sonarr.service", timeout=60)
      machine.wait_for_unit("sonarr-anime.service", timeout=60)
      machine.wait_for_unit("radarr.service", timeout=60)
      machine.wait_for_unit("lidarr.service", timeout=60)
      machine.wait_for_open_port(9696, timeout=60)
      machine.wait_for_open_port(8989, timeout=60)
      machine.wait_for_open_port(8990, timeout=60)
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
          "curl -f -H 'X-Api-Key: sonarr222222222222222222222222222' "
          "http://127.0.0.1:8990/api/v3/system/status"
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
      machine.wait_for_unit("sonarr-anime-rootfolders.service", timeout=60)
      machine.wait_for_unit("radarr-rootfolders.service", timeout=60)
      machine.wait_for_unit("lidarr-rootfolders.service", timeout=60)
      machine.wait_for_unit("prowlarr-indexers.service", timeout=60)
      machine.wait_for_unit("prowlarr-applications.service", timeout=60)

      # Verify all processes running under correct user
      machine.succeed("pgrep Prowlarr")
      machine.succeed("pgrep -u sonarr Sonarr")
      machine.succeed("pgrep -u sonarr-anime Sonarr")
      machine.succeed("pgrep -u radarr Radarr")
      machine.succeed("pgrep -u lidarr dotnet")

      # Test Prowlarr applications were configured
      print("Testing Prowlarr applications configuration...")
      applications = machine.succeed(
          "curl -s -H 'X-Api-Key: prowlarr11111111111111111111111111' "
          "http://127.0.0.1:9696/api/v1/applications"
      )

      # Verify we have 4 applications (Sonarr, Sonarr Anime, Radarr, Lidarr)
      import json
      apps = json.loads(applications)
      assert len(apps) == 4, f"Expected 4 applications, found {len(apps)}"

      # Verify each application type is present
      app_names = {app['name'] for app in apps}
      expected_apps = {'Sonarr', 'Sonarr Anime', 'Radarr', 'Lidarr'}
      assert app_names == expected_apps, f"Expected {expected_apps}, found {app_names}"

      # Verify implementation names are correct
      expected_implementations = {
          'Sonarr': 'Sonarr',
          'Sonarr Anime': 'Sonarr',
          'Radarr': 'Radarr',
          'Lidarr': 'Lidarr'
      }
      for app in apps:
          expected_impl = expected_implementations[app['name']]
          assert app['implementationName'] == expected_impl, \
              f"Implementation name mismatch for {app['name']}: expected {expected_impl}, got {app['implementationName']}"

      # Verify baseUrl is set correctly for each application
      for app in apps:
          if app['name'] == 'Sonarr':
              expected_url = "http://127.0.0.1:8989"
              actual_url = next(f['value'] for f in app['fields'] if f['name'] == 'baseUrl')
              assert actual_url == expected_url, \
                  f"Sonarr baseUrl mismatch: expected {expected_url}, got {actual_url}"
          elif app['name'] == 'Sonarr Anime':
              expected_url = "http://127.0.0.1:8990"
              actual_url = next(f['value'] for f in app['fields'] if f['name'] == 'baseUrl')
              assert actual_url == expected_url, \
                  f"Sonarr Anime baseUrl mismatch: expected {expected_url}, got {actual_url}"
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

      # Verify SABnzbd categories are configured based on enabled services
      print("Testing SABnzbd categories configuration...")
      sabnzbd_config = machine.succeed(
          "curl -s "
          "'http://127.0.0.1:8080/sabnzbd/api?mode=get_config&output=json&apikey=sabnzbd555555555555555555555555555'"
      )

      # Parse and check categories
      config_json = json.loads(sabnzbd_config)
      categories = config_json['config']['categories']
      category_names = [cat['name'] for cat in categories]

      print(f"SABnzbd categories: {category_names}")

      # Expected categories based on enabled services
      expected_categories = {'prowlarr', 'sonarr', 'sonarr-anime', 'radarr', 'lidarr', '*'}
      actual_categories = set(category_names)

      assert expected_categories == actual_categories, \
          f"Expected categories {expected_categories}, found {actual_categories}"

      # Verify each service-specific category has correct directory
      for cat in categories:
          if cat['name'] != '*':
              assert cat['dir'] == cat['name'], \
                  f"Category {cat['name']} directory mismatch: expected {cat['name']}, got {cat['dir']}"

      print("SABnzbd categories configuration verified successfully!")
      print("All services are running successfully!")
    '';
  }
