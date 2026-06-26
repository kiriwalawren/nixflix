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
  name = "maintainerr-basic-test";

  nodes.machine =
    { ... }:
    {
      imports = [ nixosModules ];

      virtualisation = {
        diskSize = 3 * 1024;
        memorySize = 4096;
        cores = 4;
      };

      environment.systemPackages = [ pkgs.jq ];

      nixflix = {
        enable = true;

        maintainerr.enable = true;

        maintainerr.settings.forceJellyfinToIgnoreEmptyMediaFolders = true;

        maintainerr.overlays.templates = [
          {
            name = "Test Pill";
            description = "Custom test overlay template";
            mode = "poster";
            canvasWidth = 1000;
            canvasHeight = 1500;
            elements = [ ];
            isDefault = true;
          }
        ];

        jellyfin = {
          enable = true;

          apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";

          users = {
            admin = {
              password._secret = pkgs.writeText "kiri_password" "321password";
              policy.isAdministrator = true;
            };
          };
        };

        seerr = {
          enable = true;
          apiKey._secret = pkgs.writeText "seerr-apikey" "seerr555555555555555555";
        };

        sonarr = {
          enable = true;
          user = "sonarr";
          mediaDirs = [ "/media/tv" ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";
          };
        };

        sonarr-anime = {
          enable = true;
          user = "sonarr-anime";
          mediaDirs = [ "/media/anime" ];
          config = {
            hostConfig = {
              port = 8990;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";
          };
        };

        radarr = {
          enable = true;
          user = "radarr";
          mediaDirs = [ "/media/movies" ];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password._secret = pkgs.writeText "radarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";
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

    # Wait for all services to start (longer timeout for initial DB migrations)
    machine.wait_for_unit("sonarr.service", timeout=180)
    machine.wait_for_unit("sonarr-anime.service", timeout=180)
    machine.wait_for_unit("radarr.service", timeout=180)

    # Wait for ports
    machine.wait_for_open_port(8989, timeout=180)
    machine.wait_for_open_port(8990, timeout=180)
    machine.wait_for_open_port(7878, timeout=180)

    # Wait for all configuration services
    machine.wait_for_unit("sonarr-config.service", timeout=60)
    machine.wait_for_unit("sonarr-anime-config.service", timeout=60)
    machine.wait_for_unit("radarr-config.service", timeout=60)

    # Wait for all services to come back up after restart
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("sonarr-anime.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(8990, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)

    # Wait for Jellyfin
    machine.wait_for_unit("jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyfin-api-key.service", timeout=300)
    machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=180)
    machine.wait_for_unit("jellyfin-system-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-plugins.service", timeout=360)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=300)
    machine.wait_for_unit("seerr.service", timeout=300)
    machine.wait_for_open_port(5055, timeout=300)

    # Wait for Seerr
    machine.wait_for_unit("seerr-setup.service", timeout=300)
    machine.wait_for_unit("seerr-user-settings.service", timeout=300)
    machine.wait_for_unit("seerr-libraries.service", timeout=300)
    machine.wait_for_unit("seerr-jellyfin.service", timeout=300)
    machine.wait_for_unit("seerr-radarr.service", timeout=300)
    machine.wait_for_unit("seerr-sonarr.service", timeout=300)

    # Wait for Maintainerr and settings provisioning
    machine.wait_for_unit("maintainerr.service", timeout=120)
    machine.wait_for_open_port(6246, timeout=120)
    machine.succeed("curl -fsS http://127.0.0.1:6246/")
    machine.wait_for_unit("maintainerr-settings.service", timeout=120)

    # Validate Maintainerr settings via API
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings | jq -e '.media_server_type == \"jellyfin\"'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings | jq -e '.jellyfin_url == \"http://127.0.0.1:8096\"'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings | jq -e '.jellyfin_api_key != null and .jellyfin_user_id != null'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings/radarr | jq -e 'length == 1 and .[0].serverName == \"Radarr\" and .[0].url == \"http://127.0.0.1:7878\"'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings/sonarr | jq -e 'length == 2'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings/sonarr | jq -e 'map(.serverName) | sort == [\"Sonarr\", \"Sonarr Anime\"]'")

    # Wait for new services introduced in recent commits
    machine.wait_for_unit("maintainerr-rules.service", timeout=120)
    machine.wait_for_unit("maintainerr-overlays.service", timeout=120)
    machine.wait_for_unit("maintainerr-overlay-templates.service", timeout=120)

    # Validate job schedules were applied (456e102: add jobs settings category)
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings | jq -e '.collection_handler_job_cron == \"0 0-23/12 * * *\"'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/settings | jq -e '.rules_handler_job_cron == \"0 0-23/8 * * *\"'")

    # Validate rule groups created by forceJellyfinIgnore (6df31e9 + 79a925b)
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/rules | jq -e 'length == 2'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/rules | jq -e 'map(.name) | sort == [\"Anime To Ignore\", \"Shows To Ignore\"]'")

    # Validate jellyfin-ignore timer is active (6df31e9)
    machine.succeed("systemctl is-active maintainerr-jellyfin-ignore.timer")

    # Trigger jellyfin-ignore service manually and verify it exits cleanly (6df31e9)
    machine.succeed("systemctl start maintainerr-jellyfin-ignore.service")

    # Validate overlay settings are applied (d32f332)
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/overlays/settings | jq -e '.enabled == true'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/overlays/settings | jq -e '.cronSchedule == \"0 */6 * * *\"'")

    # Validate overlay template was created (1f6565c)
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/overlays/templates | jq -e '[.[] | select(.isPreset == false)] | length == 1'")
    machine.succeed("curl -fsS http://127.0.0.1:6246/api/overlays/templates | jq -e '[.[] | select(.isPreset == false)] | .[0].name == \"Test Pill\"'")
  '';
}
