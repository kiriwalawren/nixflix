{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-users";

  nodes.machine = {...}: {
    imports = [nixosModules];

    networking.useDHCP = true;
    virtualisation.diskSize = 3 * 1024;

    nixflix = {
      enable = true;

      sonarr = {
        enable = true;
        mediaDirs = ["/media/tv"];
        config = {
          hostConfig = {
            username = "admin";
            password = {_secret = pkgs.writeText "sonarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";};
        };
      };

      sonarr-anime = {
        user = "sonarr-anime";
        mediaDirs = ["/media/anime"];
        config = {
          hostConfig = {
            username = "admin";
            password = {_secret = pkgs.writeText "sonarr-anime-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "sonarr-anime-apikey" "sonarr222222222222222222222222222";};
        };
      };

      radarr = {
        enable = true;
        mediaDirs = ["/media/movies"];
        config = {
          hostConfig = {
            username = "admin";
            password = {_secret = pkgs.writeText "radarr-password" "testpass";};
          };
          apiKey = {_secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";};
        };
      };

      jellyfin = {
        enable = true;

        users = {
          admin = {
            password = {_secret = pkgs.writeText "kiri_password" "321password";};
            policy.isAdministrator = true;
          };
        };
      };

      jellyseerr = {
        enable = true;
        apiKey = {_secret = pkgs.writeText "jellyseerr-apikey" "jellyseerr555555555555555555";};
      };
    };
  };

  testScript = ''
    start_all()

    port = 5055
    machine.wait_for_unit("jellyseerr.service", timeout=180)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=180)
    machine.wait_for_open_port(port, timeout=180)

    # Wait for configuration services to complete
    machine.wait_for_unit("jellyseerr-setup.service", timeout=180)
    machine.wait_for_unit("jellyseerr-user-settings.service", timeout=180)
    machine.wait_for_unit("jellyseerr-radarr.service", timeout=180)
    machine.wait_for_unit("jellyseerr-sonarr.service", timeout=180)
    machine.wait_for_unit("jellyseerr-libraries.service", timeout=180)

    cookie_file = "/run/jellyseerr/auth-cookie"
    base_url = f'http://127.0.0.1:{port}/api/v1'

    # Test API connectivity
    machine.succeed(f'curl -f -b {cookie_file} -H "Content-Type: application/json" {base_url}/settings/main')
  '';
}
