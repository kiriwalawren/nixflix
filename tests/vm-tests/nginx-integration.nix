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
  name = "nginx-integration-test";

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

        nginx = {
          enable = true;
          addHostsEntries = true;
        };

        jellyfin = {
          enable = true;
          users = {
            admin = {
              password = {
                _secret = pkgs.writeText "kiri_password" "321password";
              };
              policy.isAdministrator = true;
            };
          };
        };

        jellyseerr = {
          enable = true;
          apiKey = {
            _secret = pkgs.writeText "jellyseerr-apikey" "jellyseerr555555555555555555";
          };
        };

        prowlarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 9696;
              username = "admin";
              password = {
                _secret = pkgs.writeText "prowlarr-password" "testpass";
              };
            };
            apiKey = {
              _secret = pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111";
            };
          };
        };

        sonarr = {
          enable = true;
          user = "sonarr";
          mediaDirs = [ "/media/tv" ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password = {
                _secret = pkgs.writeText "sonarr-password" "testpass";
              };
            };
            apiKey = {
              _secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";
            };
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
              password = {
                _secret = pkgs.writeText "radarr-password" "testpass";
              };
            };
            apiKey = {
              _secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";
            };
          };
        };

        lidarr = {
          enable = true;
          user = "lidarr";
          mediaDirs = [ "/media/music" ];
          config = {
            hostConfig = {
              port = 8686;
              username = "admin";
              password = {
                _secret = pkgs.writeText "lidarr-password" "testpass";
              };
            };
            apiKey = {
              _secret = pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444";
            };
          };
        };

        sabnzbd = {
          enable = true;
          downloadsDir = "/downloads/usenet";
          settings = {
            misc = {
              api_key = {
                _secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";
              };
              nzb_key = {
                _secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbd666666666666666666666666666";
              };
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
    machine.wait_for_unit("sabnzbd.service", timeout=120)
    machine.wait_for_unit("prowlarr.service", timeout=120)
    machine.wait_for_unit("sonarr.service", timeout=120)
    machine.wait_for_unit("radarr.service", timeout=120)
    machine.wait_for_unit("lidarr.service", timeout=120)
    machine.wait_for_open_port(8080, timeout=120)
    machine.wait_for_open_port(9696, timeout=120)
    machine.wait_for_open_port(8989, timeout=120)
    machine.wait_for_open_port(7878, timeout=120)
    machine.wait_for_open_port(8686, timeout=120)

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

    # Wait for Jellyfin
    machine.wait_for_unit("jellyfin.service", timeout=180)
    machine.wait_for_open_port(8096, timeout=180)

    # Wait for jellyseerr
    machine.wait_for_unit("jellyseerr.service", timeout=300)
    machine.wait_for_open_port(5055, timeout=300)
    machine.wait_for_unit("jellyseerr-setup.service", timeout=300)

    # Test reverse proxy is proxying to Prowlarr
    print("Testing Prowlarr via reverse proxy...")
    machine.succeed(
        "curl -f http://prowlarr.internal/api/v1/system/status "
        "-H 'X-Api-Key: prowlarr11111111111111111111111111'"
    )

    # Test reverse proxy is proxying to Sonarr
    print("Testing Sonarr via reverse proxy...")
    machine.succeed(
        "curl -f http://sonarr.internal/api/v3/system/status "
        "-H 'X-Api-Key: sonarr222222222222222222222222222'"
    )

    # Test reverse proxy is proxying to Radarr
    print("Testing Radarr via reverse proxy...")
    machine.succeed(
        "curl -f http://radarr.internal/api/v3/system/status "
        "-H 'X-Api-Key: radarr333333333333333333333333333'"
    )

    # Test reverse proxy is proxying to Lidarr
    print("Testing Lidarr via reverse proxy...")
    machine.succeed(
        "curl -f http://lidarr.internal/api/v1/system/status "
        "-H 'X-Api-Key: lidarr444444444444444444444444444'"
    )

    # Test reverse proxy is proxying to SABnzbd
    print("Testing SABnzbd via reverse proxy...")
    machine.succeed(
        "curl -f 'http://sabnzbd.internal/api?mode=version&apikey=sabnzbd555555555555555555555555555'"
    )

    # Test reverse proxy is proxying to jellyfin
    api_token = machine.succeed("cat /run/jellyfin/auth-token")
    auth_header = f'"Authorization: {api_token}"'
    base_url = 'http://jellyfin.internal'
    machine.succeed(f'curl -f -H {auth_header} {base_url}/System/Info')

    # Test reverse proxy is proxying to jellyseerr
    machine.succeed('curl -f "http://jellyseerr.internal/api/v1/status"')

    print("Reverse proxy integration test successful! All services accessible via subdomains.")
  '';
}
