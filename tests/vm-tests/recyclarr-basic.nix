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
  name = "recyclarr-basic-test";

  nodes.machine =
    { pkgs, lib, ... }:
    {
      imports = [ nixosModules ];

      networking.useDHCP = true;

      virtualisation = {
        cores = 4;
        memorySize = 4096;
        diskSize = 3 * 1024;
      };

      nixflix = {
        enable = true;

        radarr = {
          enable = true;
          mediaDirs = [ "/media/movies" ];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password._secret = pkgs.writeText "radarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";
          };
        };

        sonarr = {
          enable = true;
          mediaDirs = [ "/media/tv" ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpassword456";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "efgh5678efgh5678efgh5678efgh5678";
          };
        };

        sonarr-anime = {
          enable = true;
          mediaDirs = [ "/media/anime" ];
          config = {
            hostConfig = {
              port = 8990;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-anime-password" "testpassword789";
            };
            apiKey._secret = pkgs.writeText "sonarr-anime-apikey" "ijkl9012ijkl9012ijkl9012ijkl9012";
          };
        };

        recyclarr = {
          enable = true;
          cleanupUnmanagedProfiles.enable = true;
        };

        jellyfin = {
          enable = true;

          apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";

          users = {
            admin = {
              password._secret = pkgs.writeText "kiri_password" "321password";
              policy.isAdministrator = true;
            };
          };

          # Disable AniDB to keep test pure
          plugins.AniDB.enable = false;
          libraries.Anime.typeOptions = lib.mkForce [ ];
        };

        seerr = {
          enable = true;
          apiKey._secret = pkgs.writeText "seerr-apikey" "seerr555555555555555555";
        };
      };

      systemd.services.jellyfin.serviceConfig.TimeoutStartSec = lib.mkForce 300;
    };

  testScript = ''
    import json

    start_all()

    # Wait for all services to start
    machine.wait_for_unit("radarr.service", timeout=180)
    machine.wait_for_unit("sonarr.service", timeout=180)
    machine.wait_for_unit("sonarr-anime.service", timeout=180)
    machine.wait_for_open_port(7878, timeout=180)
    machine.wait_for_open_port(8989, timeout=180)
    machine.wait_for_open_port(8990, timeout=180)

    # Wait for config services to complete
    machine.wait_for_unit("radarr-config.service", timeout=180)
    machine.wait_for_unit("sonarr-config.service", timeout=180)
    machine.wait_for_unit("sonarr-anime-config.service", timeout=180)

    # Wait for services to come back up after config restarts
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("sonarr-anime.service", timeout=60)
    machine.wait_for_open_port(7878, timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(8990, timeout=60)

    # Wait for recyclarr to complete
    machine.wait_until_succeeds(
        "systemctl show recyclarr.service -p SubState | grep -q 'SubState=dead' && "
        "systemctl show recyclarr.service -p ActiveEnterTimestamp | grep -q 'ActiveEnterTimestamp=\n' && "
        "systemctl show recyclarr.service -p Result | grep -q 'Result=success'",
        timeout=180
    )
    machine.wait_until_succeeds(
        "systemctl show recyclarr-cleanup-profiles.service -p SubState | grep -q 'SubState=dead' && "
        "systemctl show recyclarr-cleanup-profiles.service -p ActiveEnterTimestamp | grep -q 'ActiveEnterTimestamp=\n' && "
        "systemctl show recyclarr-cleanup-profiles.service -p Result | grep -q 'Result=success'",
        timeout=180
    )

    # Wait for jellyfin to complete
    machine.wait_for_unit("jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyfin-api-key.service", timeout=300)
    machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=180)
    machine.wait_for_unit("jellyfin-system-config.service", timeout=180)
    machine.wait_for_unit("jellyfin-plugins.service", timeout=360)
    machine.wait_for_unit("jellyfin-libraries.service", timeout=300)

    # Wait for seerr to complete
    machine.wait_for_unit("seerr.service", timeout=300)
    machine.wait_for_open_port(5055, timeout=300)
    machine.wait_for_unit("seerr-setup.service", timeout=300)
    machine.wait_for_unit("seerr-radarr.service", timeout=300)
    machine.wait_for_unit("seerr-sonarr.service", timeout=300)

    # Check that quality profiles were created by recyclarr for Radarr
    radarr_profiles = machine.succeed(
        "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
        "http://127.0.0.1:7878/api/v3/qualityprofile"
    )
    radarr_profiles_list = json.loads(radarr_profiles)

    radarr_profile_names = {p['name'] for p in radarr_profiles_list}
    assert radarr_profile_names == {"[SQP] SQP-1 (1080p)"}, \
        f"Expected only '[SQP] SQP-1 (1080p)' in Radarr after cleanup, found: {radarr_profile_names}"

    # Check that quality profiles were created by recyclarr for Sonarr
    sonarr_profiles = machine.succeed(
        "curl -s -H 'X-Api-Key: efgh5678efgh5678efgh5678efgh5678' "
        "http://127.0.0.1:8989/api/v3/qualityprofile"
    )
    sonarr_profiles_list = json.loads(sonarr_profiles)

    sonarr_profile_names = {p['name'] for p in sonarr_profiles_list}
    assert sonarr_profile_names == {"WEB-1080p (Alternative)"}, \
        f"Expected only 'WEB-1080p (Alternative)' in Sonarr after cleanup, found: {sonarr_profile_names}"

    # Check that quality profiles were created by recyclarr for Sonarr-Anime
    sonarr_anime_profiles = machine.succeed(
        "curl -s -H 'X-Api-Key: ijkl9012ijkl9012ijkl9012ijkl9012' "
        "http://127.0.0.1:8990/api/v3/qualityprofile"
    )
    sonarr_anime_profiles_list = json.loads(sonarr_anime_profiles)

    sonarr_anime_profile_names = {p['name'] for p in sonarr_anime_profiles_list}
    assert sonarr_anime_profile_names == {"[Anime] Remux-1080p"}, \
        f"Expected only '[Anime] Remux-1080p' in Sonarr-Anime after cleanup, found: {sonarr_anime_profile_names}"

    # Wait for cleanup-profiles service to complete
    machine.wait_until_succeeds(
        "systemctl show recyclarr-cleanup-profiles.service -p SubState | grep -q 'SubState=dead' && "
        "systemctl show recyclarr-cleanup-profiles.service -p ActiveEnterTimestamp | grep -q 'ActiveEnterTimestamp=\n' && "
        "systemctl show recyclarr-cleanup-profiles.service -p Result | grep -q 'Result=success'",
        timeout=60
    )

    # Verify API keys are not visible in process arguments
    result = machine.succeed("ps aux")
    assert "abcd1234abcd1234abcd1234abcd1234" not in result, \
        "Radarr API key found in process list! Security vulnerability!"
    assert "efgh5678efgh5678efgh5678efgh5678" not in result, \
        "Sonarr API key found in process list! Security vulnerability!"
    assert "ijkl9012ijkl9012ijkl9012ijkl9012" not in result, \
        "Sonarr-Anime API key found in process list! Security vulnerability!"

    # Check that no API keys are visible in /proc/*/cmdline
    for api_key in ["abcd1234abcd1234abcd1234abcd1234",
                    "efgh5678efgh5678efgh5678efgh5678",
                    "ijkl9012ijkl9012ijkl9012ijkl9012"]:
        cmdline_check = machine.succeed(
            f"find /proc -name cmdline -type f 2>/dev/null | "
            f"xargs cat 2>/dev/null | "
            f"grep -q {api_key} && echo 'FOUND' || echo 'NOT_FOUND'"
        )
        assert "NOT_FOUND" in cmdline_check, \
            f"API key {api_key} found in /proc/*/cmdline! Security vulnerability!"
  '';
}
