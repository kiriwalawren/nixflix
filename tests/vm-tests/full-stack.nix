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
        user = "mediauser";
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
        user = "mediauser";
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
        user = "mediauser";
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

    # Wait for all services to start
    machine.wait_for_unit("prowlarr.service", timeout=20)
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_unit("lidarr.service", timeout=20)

    # Wait for ports
    machine.wait_for_open_port(9696, timeout=20)
    machine.wait_for_open_port(8989, timeout=20)
    machine.wait_for_open_port(7878, timeout=20)
    machine.wait_for_open_port(8686, timeout=20)

    # Wait for all configuration services
    machine.wait_for_unit("prowlarr-config.service", timeout=20)
    machine.wait_for_unit("sonarr-config.service", timeout=20)
    machine.wait_for_unit("radarr-config.service", timeout=20)
    machine.wait_for_unit("lidarr-config.service", timeout=20)

    # Wait for all services to come back up after restart
    machine.wait_for_unit("prowlarr.service", timeout=20)
    machine.wait_for_unit("sonarr.service", timeout=20)
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_unit("lidarr.service", timeout=20)
    machine.wait_for_open_port(9696, timeout=20)
    machine.wait_for_open_port(8989, timeout=20)
    machine.wait_for_open_port(7878, timeout=20)
    machine.wait_for_open_port(8686, timeout=20)

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
    machine.wait_for_unit("sonarr-rootfolders.service", timeout=20)
    machine.wait_for_unit("radarr-rootfolders.service", timeout=20)
    machine.wait_for_unit("lidarr-rootfolders.service", timeout=20)

    # Verify all processes running under correct user
    machine.succeed("pgrep Prowlarr")
    machine.succeed("pgrep -u mediauser Sonarr")
    machine.succeed("pgrep -u mediauser Radarr")
    machine.succeed("pgrep -u mediauser dotnet")

    print("All services are running successfully!")
  '';
}
