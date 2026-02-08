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
    name = "recyclarr-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      networking.useDHCP = true;
      virtualisation.cores = 4;

      nixflix = {
        enable = true;

        radarr = {
          enable = true;
          user = "radarr";
          mediaDirs = ["/media/movies"];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password = {_secret = pkgs.writeText "radarr-password" "testpassword123";};
            };
            apiKey = {_secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";};
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
              password = {_secret = pkgs.writeText "sonarr-password" "testpassword456";};
            };
            apiKey = {_secret = pkgs.writeText "sonarr-apikey" "efgh5678efgh5678efgh5678efgh5678";};
          };
        };

        sonarr-anime = {
          enable = true;
          user = "sonarr-anime";
          mediaDirs = ["/media/anime"];
          config = {
            hostConfig = {
              port = 8990;
              username = "admin";
              password = {_secret = pkgs.writeText "sonarr-anime-password" "testpassword789";};
            };
            apiKey = {_secret = pkgs.writeText "sonarr-anime-apikey" "ijkl9012ijkl9012ijkl9012ijkl9012";};
          };
        };

        recyclarr = {
          enable = true;
          radarr.enable = true;
          sonarr.enable = true;
          sonarr-anime.enable = true;
          cleanupUnmanagedProfiles = true;
        };
      };
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

      # Test API connectivity for all services
      machine.succeed(
          "curl -f -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/system/status"
      )
      machine.succeed(
          "curl -f -H 'X-Api-Key: efgh5678efgh5678efgh5678efgh5678' "
          "http://127.0.0.1:8989/api/v3/system/status"
      )
      machine.succeed(
          "curl -f -H 'X-Api-Key: ijkl9012ijkl9012ijkl9012ijkl9012' "
          "http://127.0.0.1:8990/api/v3/system/status"
      )

      # Wait for recyclarr to complete
      machine.wait_until_succeeds(
          "systemctl show recyclarr.service -p SubState | grep -q 'SubState=dead' && "
          "systemctl show recyclarr.service -p ActiveEnterTimestamp | grep -q 'ActiveEnterTimestamp=\n' && "
          "systemctl show recyclarr.service -p Result | grep -q 'Result=success'",
          timeout=180
      )

      # Check that quality profiles were created by recyclarr for Radarr
      radarr_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/qualityprofile"
      )
      radarr_profiles_list = json.loads(radarr_profiles)

      radarr_profile_names = [p['name'] for p in radarr_profiles_list]
      assert "UHD Bluray + WEB" in radarr_profile_names, \
          f"Expected 'UHD Bluray + WEB' profile from recyclarr in Radarr, found: {radarr_profile_names}"

      # Check that quality profiles were created by recyclarr for Sonarr
      sonarr_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: efgh5678efgh5678efgh5678efgh5678' "
          "http://127.0.0.1:8989/api/v3/qualityprofile"
      )
      sonarr_profiles_list = json.loads(sonarr_profiles)

      sonarr_profile_names = [p['name'] for p in sonarr_profiles_list]
      # Sonarr should have both normal and anime profiles when sonarr-anime is enabled
      assert "WEB-1080p" in sonarr_profile_names, \
          f"Expected 'WEB-1080p' profile from recyclarr in Sonarr, found: {sonarr_profile_names}"
      assert len(sonarr_profiles_list) > 1, \
          f"Expected multiple quality profiles in Sonarr, found: {len(sonarr_profiles_list)}"

      # Check that quality profiles were created by recyclarr for Sonarr-Anime
      sonarr_anime_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: ijkl9012ijkl9012ijkl9012ijkl9012' "
          "http://127.0.0.1:8990/api/v3/qualityprofile"
      )
      sonarr_anime_profiles_list = json.loads(sonarr_anime_profiles)

      sonarr_anime_profile_names = [p['name'] for p in sonarr_anime_profiles_list]
      assert "Remux-1080p - Anime" in sonarr_anime_profile_names, \
          f"Expected 'Remux-1080p - Anime' profile from recyclarr in Sonarr-Anime, found: {sonarr_anime_profile_names}"

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

      # Verify the cleanup script exists and uses mkSecureCurl pattern (curl --variable)
      cleanup_script = machine.succeed(
          "cat /nix/store/*-cleanup-quality-profiles.sh | head -200"
      )

      # Check that the script uses curl with --variable (secure pattern)
      assert "--variable apiKey@" in cleanup_script, \
          "Cleanup script should use 'curl --variable apiKey@' for security"
      assert "--expand-header" in cleanup_script, \
          "Cleanup script should use '--expand-header' with curl variables"

      # Verify multiple instances are handled (should have multiple sections for radarr, sonarr, sonarr-anime)
      assert cleanup_script.count("Processing") >= 3, \
          "Cleanup script should process at least 3 instances (radarr, sonarr, sonarr-anime)"
      assert "radarr" in cleanup_script.lower(), \
          "Cleanup script should mention radarr instance"
      assert "sonarr" in cleanup_script.lower(), \
          "Cleanup script should mention sonarr instance"
    '';
  }
