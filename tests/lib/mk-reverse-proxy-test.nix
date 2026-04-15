# Shared integration test for reverse proxy backends (nginx/caddy).
#
# Takes a proxy config attrset and returns a NixOS VM test that verifies:
# - All exposed services are accessible via their subdomain
# - Services with `reverseProxy.expose = false` are NOT proxied
# - Unexposed services are still reachable on localhost
{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
  # e.g. { caddy = { enable = true; addHostsEntries = true; }; }
  # or   { nginx = { enable = true; addHostsEntries = true; }; }
  proxyConfig,
  testName,
}:
let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };

  proxyService =
    if (proxyConfig ? caddy && proxyConfig.caddy.enable or false) then "caddy" else "nginx";
in
pkgsUnfree.testers.runNixOSTest {
  name = testName;

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

        prowlarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 9696;
              username = "admin";
              password._secret = pkgs.writeText "prowlarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111";
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
              password._secret = pkgs.writeText "sonarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "sonarr222222222222222222222222222";
          };
        };

        # Custom subdomain to test subdomain override
        radarr = {
          enable = true;
          user = "radarr";
          mediaDirs = [ "/media/movies" ];
          subdomain = "movies";
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password._secret = pkgs.writeText "radarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";
          };
        };

        # Lidarr has expose=false to test unexposed services
        lidarr = {
          enable = true;
          user = "lidarr";
          mediaDirs = [ "/media/music" ];
          reverseProxy.expose = false;
          config = {
            hostConfig = {
              port = 8686;
              username = "admin";
              password._secret = pkgs.writeText "lidarr-password" "testpass";
            };
            apiKey._secret = pkgs.writeText "lidarr-apikey" "lidarr444444444444444444444444444";
          };
        };

        usenetClients.sabnzbd = {
          enable = true;
          downloadsDir = "/downloads/usenet";
          settings = {
            misc = {
              api_key._secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";
              nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbd666666666666666666666666666";
              port = 8080;
              host = "127.0.0.1";
            };
          };
        };
      }
      // proxyConfig;
    };

  testScript = ''
    start_all()

    # Wait for reverse proxy
    machine.wait_for_unit("${proxyService}.service", timeout=60)
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
    machine.wait_for_unit("jellyfin-api-key.service", timeout=180)
    machine.wait_for_open_port(8096, timeout=180)

    # Wait for seerr
    machine.wait_for_unit("seerr.service", timeout=300)
    machine.wait_for_open_port(5055, timeout=300)
    machine.wait_for_unit("seerr-setup.service", timeout=300)

    # --- Test exposed services are accessible via reverse proxy ---

    print("Testing Prowlarr via reverse proxy...")
    machine.succeed(
        "curl -f http://prowlarr.nixflix/api/v1/system/status "
        "-H 'X-Api-Key: prowlarr11111111111111111111111111'"
    )

    print("Testing Sonarr via reverse proxy...")
    machine.succeed(
        "curl -f http://sonarr.nixflix/api/v3/system/status "
        "-H 'X-Api-Key: sonarr222222222222222222222222222'"
    )

    # Radarr uses a custom subdomain (subdomain = "movies")
    print("Testing Radarr via custom subdomain (movies.nixflix)...")
    machine.succeed(
        "curl -f http://movies.nixflix/api/v3/system/status "
        "-H 'X-Api-Key: radarr333333333333333333333333333'"
    )

    print("Testing Radarr is NOT accessible at default subdomain (radarr.nixflix)...")
    machine.fail(
        "curl -f http://radarr.nixflix/api/v3/system/status "
        "-H 'X-Api-Key: radarr333333333333333333333333333'"
    )

    print("Testing SABnzbd via reverse proxy...")
    machine.succeed(
        "curl -f 'http://sabnzbd.nixflix/api?mode=version&apikey=sabnzbd555555555555555555555555555'"
    )

    print("Testing Jellyfin via reverse proxy...")
    api_token = machine.succeed("cat /run/jellyfin/auth-token")
    auth_header = f'"Authorization: {api_token}"'
    base_url = 'http://jellyfin.nixflix'
    machine.succeed(f'curl -f -H {auth_header} {base_url}/System/Info')

    print("Testing Seerr via reverse proxy...")
    machine.succeed('curl -f "http://seerr.nixflix/api/v1/status"')

    # --- Test unexposed service (lidarr) is NOT accessible via reverse proxy ---

    print("Testing Lidarr is NOT accessible via reverse proxy...")
    machine.fail("curl -f http://lidarr.nixflix/api/v1/system/status "
        "-H 'X-Api-Key: lidarr444444444444444444444444444'")

    print("Testing Lidarr is still accessible on localhost...")
    machine.succeed(
        "curl -f http://127.0.0.1:8686/api/v1/system/status "
        "-H 'X-Api-Key: lidarr444444444444444444444444444'"
    )

    # Verify no hosts entry was created for the unexposed service
    machine.fail("grep -q 'lidarr.nixflix' /etc/hosts")

    print("${testName} successful! Exposed services proxied, unexposed services correctly hidden.")
  '';
}
