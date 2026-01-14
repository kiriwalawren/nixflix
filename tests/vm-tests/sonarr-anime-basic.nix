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
    name = "sonarr-anime-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        sonarr-anime = {
          enable = true;
          user = "testuser";
          mediaDirs = ["/media/anime"];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              passwordPath = "${pkgs.writeText "sonarr-anime-password" "testpassword123"}";
            };
            apiKeyPath = "${pkgs.writeText "sonarr-anime-apikey" "0123456789abcdef0123456789abcdef"}";
            delayProfiles = [
              {
                enableUsenet = true;
                enableTorrent = true;
                preferredProtocol = "torrent";
                usenetDelay = 0;
                torrentDelay = 360;
                bypassIfHighestQuality = true;
                bypassIfAboveCustomFormatScore = false;
                minimumCustomFormatScore = 0;
                order = 2147483647;
                tags = [];
                id = 1;
              }
            ];
          };
        };

        sabnzbd = {
          enable = true;
          settings = {
            api_key = {_secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";};
            nzb_key = {_secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbdnzb666666666666666666666";};
            port = 8080;
            host = "127.0.0.1";
            url_base = "/sabnzbd";
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for services to start (longer timeout for initial DB migrations)
      machine.wait_for_unit("sonarr-anime.service", timeout=180)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(8989, timeout=180)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("sonarr-anime-config.service", timeout=180)

      # Wait for sonarr-anime to come back up after restart
      machine.wait_for_unit("sonarr-anime.service", timeout=60)
      machine.wait_for_open_port(8989, timeout=60)

      # Test API connectivity with the configured API key
      machine.succeed(
          "curl -f -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/system/status"
      )

      # Check that host configuration was applied
      result = machine.succeed(
          "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/config/host"
      )
      print(f"Host config: {result}")

      # Verify username is set correctly
      assert "admin" in result, "Username not configured correctly"

      # Wait for root folders, delay profiles, and download clients services
      machine.wait_for_unit("sonarr-anime-rootfolders.service", timeout=60)
      machine.wait_for_unit("sonarr-anime-delayprofiles.service", timeout=60)
      machine.wait_for_unit("sonarr-anime-downloadclients.service", timeout=60)

      # Check that root folder was created
      folders = machine.succeed(
          "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/rootfolder"
      )
      print(f"Root folders: {folders}")
      assert "/media/anime" in folders, "Root folder not created"

      # Check that SABnzbd download client was configured
      import json
      clients = machine.succeed(
          "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/downloadclient"
      )
      clients_list = json.loads(clients)
      print(f"Download clients: {clients}")
      assert len(clients_list) == 1, f"Expected 1 download client, found {len(clients_list)}"
      assert clients_list[0]['name'] == 'SABnzbd', \
          f"Expected SABnzbd download client, found {clients_list[0]['name']}"
      assert clients_list[0]['implementationName'] == 'SABnzbd', \
          "Expected SABnzbd implementation"

      # Check that the tvCategory is set to 'sonarr-anime'
      category_field = next((field for field in clients_list[0]['fields'] if field['name'] == 'tvCategory'), None)
      assert category_field is not None, "Expected tvCategory field in SABnzbd download client"
      assert category_field['value'] == 'sonarr-anime', \
          f"Expected tvCategory 'sonarr-anime', found '{category_field['value']}'"
      print("SABnzbd download client configured successfully with sonarr-anime category!")

      # Check that default delay profile was created
      delay_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/delayprofile"
      )
      profiles_list = json.loads(delay_profiles)
      print(f"Delay profiles: {delay_profiles}")
      assert len(profiles_list) == 1, f"Expected 1 delay profile, found {len(profiles_list)}"
      assert profiles_list[0]['id'] == 1, "Expected default delay profile with id=1"
      assert profiles_list[0]['enableUsenet'] == True, "Expected enableUsenet=true"
      assert profiles_list[0]['enableTorrent'] == True, "Expected enableTorrent=true"
      assert profiles_list[0]['preferredProtocol'] == 'torrent', "Expected preferredProtocol=torrent"
      assert profiles_list[0]['usenetDelay'] == 0, "Expected usenetDelay=0"
      assert profiles_list[0]['torrentDelay'] == 360, "Expected torrentDelay=360"
      assert profiles_list[0]['order'] == 2147483647, "Expected order=2147483647"
      print("Default delay profile configured successfully!")

      # Verify the service is running under the correct user
      machine.succeed("pgrep -u testuser Sonarr")
    '';
  }
