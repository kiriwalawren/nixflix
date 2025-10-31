{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "nginx-integration-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;
      nginx.enable = true;
      serviceNameIsUrlBase = true;

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
        mediaDirs = [{dir = "/media/tv";}];
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
        mediaDirs = [{dir = "/media/movies";}];
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
        mediaDirs = [{dir = "/media/music";}];
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

    # Wait for nginx
    machine.wait_for_unit("nginx.service", timeout=20)
    machine.wait_for_open_port(80, timeout=20)

    # Wait for all services
    machine.wait_for_unit("prowlarr.service", timeout=20)
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_unit("lidarr.service", timeout=20)
    machine.wait_for_open_port(9696, timeout=20)
    machine.wait_for_open_port(8989, timeout=20)
    machine.wait_for_open_port(7878, timeout=20)
    machine.wait_for_open_port(8686, timeout=20)

    # Wait for configuration services
    machine.wait_for_unit("prowlarr-config.service", timeout=20)
    machine.wait_for_unit("sonarr-config.service", timeout=20)
    machine.wait_for_unit("radarr-config.service", timeout=20)
    machine.wait_for_unit("lidarr-config.service", timeout=20)

    # Wait for services to come back up after restart
    machine.wait_for_unit("prowlarr.service", timeout=20)
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_unit("lidarr.service", timeout=20)
    machine.wait_for_open_port(9696, timeout=20)
    machine.wait_for_open_port(8989, timeout=20)
    machine.wait_for_open_port(7878, timeout=20)
    machine.wait_for_open_port(8686, timeout=20)

    # Test nginx is proxying to Prowlarr
    print("Testing Prowlarr via nginx...")
    machine.succeed(
        "curl -f http://localhost/prowlarr/api/v1/system/status "
        "-H 'X-Api-Key: prowlarr11111111111111111111111111'"
    )

    # Test nginx is proxying to Sonarr
    print("Testing Sonarr via nginx...")
    machine.succeed(
        "curl -f http://localhost/sonarr/api/v3/system/status "
        "-H 'X-Api-Key: sonarr222222222222222222222222222'"
    )

    # Test nginx is proxying to Radarr
    print("Testing Radarr via nginx...")
    machine.succeed(
        "curl -f http://localhost/radarr/api/v3/system/status "
        "-H 'X-Api-Key: radarr333333333333333333333333333'"
    )

    # Test nginx is proxying to Lidarr
    print("Testing Lidarr via nginx...")
    machine.succeed(
        "curl -f http://localhost/lidarr/api/v1/system/status "
        "-H 'X-Api-Key: lidarr444444444444444444444444444'"
    )

    print("Nginx integration test successful! All services accessible via reverse proxy.")
  '';
}
