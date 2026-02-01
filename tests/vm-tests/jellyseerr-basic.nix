{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-users";

  nodes.machine = {lib, ...}: {
    imports = [nixosModules];

    networking.useDHCP = true;
    virtualisation = {
      diskSize = 3 * 1024;
      cores = 4;
    };

    nixflix = {
      enable = true;

      recyclarr.enable = false;

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
        enable = true;
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

    # Increase timeout for CI environments where Jellyfin may start slower
    systemd.services.jellyfin.serviceConfig.TimeoutStartSec = lib.mkForce 300;
  };

  testScript = ''
    start_all()

    port = 5055
    machine.wait_for_unit("jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=300)
    machine.wait_for_unit("jellyseerr.service", timeout=300)
    machine.wait_for_open_port(port, timeout=300)

    # Wait for configuration services to complete
    machine.wait_for_unit("jellyseerr-setup.service", timeout=300)
    machine.wait_for_unit("jellyseerr-user-settings.service", timeout=300)
    machine.wait_for_unit("jellyseerr-libraries.service", timeout=300)
    machine.wait_for_unit("jellyseerr-jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyseerr-radarr.service", timeout=300)
    machine.wait_for_unit("jellyseerr-sonarr.service", timeout=300)

    cookie_file = "/run/jellyseerr/auth-cookie"
    base_url = f'http://127.0.0.1:{port}/api/v1'

    # Test API connectivity
    machine.succeed(f'curl -f -b {cookie_file} -H "Content-Type: application/json" {base_url}/settings/main')

    import json

    # Validate Radarr configuration
    radarr_json = machine.succeed(f'curl -f -b {cookie_file} -H "Content-Type: application/json" {base_url}/settings/radarr')
    radarr_instances = json.loads(radarr_json)

    assert len(radarr_instances) == 1, f"Expected 1 Radarr instance, found {len(radarr_instances)}"

    radarr = radarr_instances[0]
    assert radarr['name'] == 'Radarr', f"Expected name 'Radarr', got {radarr.get('name')}"
    assert radarr['hostname'] == '127.0.0.1', f"Expected hostname '127.0.0.1', got {radarr.get('hostname')}"
    assert radarr['port'] == 7878, f"Expected port 7878, got {radarr.get('port')}"
    assert radarr['useSsl'] == False, f"Expected useSsl False, got {radarr.get('useSsl')}"
    assert radarr['baseUrl'] == "", f"Expected baseUrl empty, got {radarr.get('baseUrl')}"
    assert radarr['is4k'] == False, f"Expected is4k False, got {radarr.get('is4k')}"
    assert radarr['isDefault'] == True, f"Expected isDefault True, got {radarr.get('isDefault')}"
    assert radarr['syncEnabled'] == False, f"Expected syncEnabled False, got {radarr.get('syncEnabled')}"
    assert radarr['preventSearch'] == False, f"Expected preventSearch False, got {radarr.get('preventSearch')}"
    assert radarr['activeDirectory'] == '/media/movies', f"Expected activeDirectory '/media/movies', got {radarr.get('activeDirectory')}"
    assert radarr['minimumAvailability'] in ['announced', 'inCinemas', 'released'], f"Expected valid minimumAvailability, got {radarr.get('minimumAvailability')}"

    # Validate Sonarr configuration
    sonarr_json = machine.succeed(f'curl -f -b {cookie_file} -H "Content-Type: application/json" {base_url}/settings/sonarr')
    sonarr_instances = json.loads(sonarr_json)

    assert len(sonarr_instances) == 2, f"Expected 2 Sonarr instances, found {len(sonarr_instances)}"

    # Find Sonarr instance
    sonarr_main = [s for s in sonarr_instances if s['name'] == 'Sonarr']
    assert len(sonarr_main) == 1, f"Expected 1 'Sonarr' instance, found {len(sonarr_main)}"
    sonarr = sonarr_main[0]

    assert sonarr['hostname'] == '127.0.0.1', f"Expected hostname '127.0.0.1', got {sonarr.get('hostname')}"
    assert sonarr['port'] == 8989, f"Expected port 8989, got {sonarr.get('port')}"
    assert sonarr['useSsl'] == False, f"Expected useSsl False, got {sonarr.get('useSsl')}"
    assert sonarr['baseUrl'] == "", f"Expected baseUrl empty, got {sonarr.get('baseUrl')}"
    assert sonarr['is4k'] == False, f"Expected is4k False, got {sonarr.get('is4k')}"
    assert sonarr['isDefault'] == True, f"Expected isDefault True, got {sonarr.get('isDefault')}"
    assert sonarr['enableSeasonFolders'] == True, f"Expected enableSeasonFolders True, got {sonarr.get('enableSeasonFolders')}"
    assert sonarr['syncEnabled'] == False, f"Expected syncEnabled False, got {sonarr.get('syncEnabled')}"
    assert sonarr['preventSearch'] == False, f"Expected preventSearch False, got {sonarr.get('preventSearch')}"
    assert sonarr['activeDirectory'] == '/media/tv', f"Expected activeDirectory '/media/tv', got {sonarr.get('activeDirectory')}"

    # Find Sonarr Anime instance
    sonarr_anime = [s for s in sonarr_instances if s['name'] == 'Sonarr Anime']
    assert len(sonarr_anime) == 1, f"Expected 1 'Sonarr Anime' instance, found {len(sonarr_anime)}"
    anime = sonarr_anime[0]

    assert anime['hostname'] == '127.0.0.1', f"Expected hostname '127.0.0.1', got {anime.get('hostname')}"
    assert anime['port'] == 8990, f"Expected port 8990 for anime instance, got {anime.get('port')}"
    assert anime['useSsl'] == False, f"Expected useSsl False, got {anime.get('useSsl')}"
    assert anime['baseUrl'] == "", f"Expected baseUrl empty, got {anime.get('baseUrl')}"
    assert anime['is4k'] == False, f"Expected is4k False, got {anime.get('is4k')}"
    assert anime['isDefault'] == False, f"Expected isDefault False, got {anime.get('isDefault')}"
    assert anime['enableSeasonFolders'] == True, f"Expected enableSeasonFolders True, got {anime.get('enableSeasonFolders')}"
    assert anime['syncEnabled'] == False, f"Expected syncEnabled False, got {anime.get('syncEnabled')}"
    assert anime['preventSearch'] == False, f"Expected preventSearch False, got {anime.get('preventSearch')}"
    assert anime['activeDirectory'] == '/media/anime', f"Expected activeDirectory '/media/anime', got {anime.get('activeDirectory')}"
  '';
}
