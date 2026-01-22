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
    name = "nginx-integration-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      nixflix = {
        enable = true;
        nginx.enable = true;

        prowlarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 9696;
              username = "admin";
              password = {_secret = toString (pkgs.writeText "prowlarr-password" "testpass");};
            };
            apiKey = {_secret = toString (pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111");};
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
              password = {_secret = toString (pkgs.writeText "sonarr-password" "testpass");};
            };
            apiKey = {_secret = toString (pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222");};
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
              password = {_secret = toString (pkgs.writeText "radarr-password" "testpass");};
            };
            apiKey = {_secret = toString (pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333");};
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
              password = {_secret = toString (pkgs.writeText "lidarr-password" "testpass");};
            };
            apiKey = {_secret = toString (pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444");};
          };
        };

        sabnzbd = {
          enable = true;
          downloadsDir = "/downloads/usenet";
          settings = {
            misc = {
              api_key = {_secret = toString (pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555");};
              nzb_key = {_secret = toString (pkgs.writeText "sabnzbd-nzbkey" "sabnzbd666666666666666666666666666");};
              port = 8080;
              host = "127.0.0.1";
            };
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for nginx
      machine.wait_for_unit("nginx.service", timeout=60)
      machine.wait_for_open_port(80, timeout=60)

      # Wait for all services
      machine.wait_for_unit("prowlarr.service", timeout=120)
      machine.wait_for_unit("sonarr.service", timeout=120)
      machine.wait_for_unit("radarr.service", timeout=120)
      machine.wait_for_unit("lidarr.service", timeout=120)
      machine.wait_for_unit("sabnzbd.service", timeout=120)
      machine.wait_for_open_port(9696, timeout=120)
      machine.wait_for_open_port(8989, timeout=120)
      machine.wait_for_open_port(7878, timeout=120)
      machine.wait_for_open_port(8686, timeout=120)
      machine.wait_for_open_port(8080, timeout=120)

      # Wait for configuration services
      machine.wait_for_unit("prowlarr-config.service", timeout=60)
      machine.wait_for_unit("sonarr-config.service", timeout=60)
      machine.wait_for_unit("radarr-config.service", timeout=60)
      machine.wait_for_unit("lidarr-config.service", timeout=60)

      # Wait for services to come back up after restart
      machine.wait_for_unit("prowlarr.service", timeout=60)
      machine.wait_for_unit("sonarr.service", timeout=60)
      machine.wait_for_unit("radarr.service", timeout=60)
      machine.wait_for_unit("lidarr.service", timeout=60)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(9696, timeout=60)
      machine.wait_for_open_port(8989, timeout=60)
      machine.wait_for_open_port(7878, timeout=60)
      machine.wait_for_open_port(8686, timeout=60)
      machine.wait_for_open_port(8080, timeout=60)

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

      # Test nginx is proxying to SABnzbd
      print("Testing SABnzbd via nginx...")
      machine.succeed(
          "curl -f http://localhost/sabnzbd/api?mode=version&apikey=sabnzbd555555555555555555555555555"
      )

      print("Nginx integration test successful! All services accessible via reverse proxy.")
    '';
  }
