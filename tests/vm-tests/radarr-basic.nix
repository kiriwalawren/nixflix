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
    name = "radarr-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      virtualisation.cores = 4;

      nixflix = {
        enable = true;

        radarr = {
          enable = true;
          user = "testuser";
          mediaDirs = ["/media/movies"];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password = {_secret = pkgs.writeText "radarr-password" "testpassword123";};
            };
            apiKey = {_secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";};
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
            misc = {
              api_key = {_secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";};
              nzb_key = {_secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbdnzb666666666666666666666";};
              port = 8080;
              host = "127.0.0.1";
              url_base = "/sabnzbd";
            };
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for services to start (longer timeout for initial DB migrations)
      machine.wait_for_unit("radarr.service", timeout=180)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(7878, timeout=180)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("radarr-config.service", timeout=180)

      # Wait for radarr to come back up after restart
      machine.wait_for_unit("radarr.service", timeout=60)
      machine.wait_for_open_port(7878, timeout=60)

      # Test API connectivity
      machine.succeed(
          "curl -f -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/system/status"
      )

      # Wait for root folders, delay profiles, and download clients services
      machine.wait_for_unit("radarr-rootfolders.service", timeout=60)
      machine.wait_for_unit("radarr-delayprofiles.service", timeout=60)
      machine.wait_for_unit("radarr-downloadclients.service", timeout=60)

      # Check root folder
      folders = machine.succeed(
          "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/rootfolder"
      )
      print(f"Root folders: {folders}")
      assert "/media/movies" in folders, "Root folder not created"

      # Check that SABnzbd download client was configured
      import json
      clients = machine.succeed(
          "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/downloadclient"
      )
      clients_list = json.loads(clients)
      print(f"Download clients: {clients}")
      assert len(clients_list) == 1, f"Expected 1 download client, found {len(clients_list)}"
      assert clients_list[0]['name'] == 'SABnzbd', \
          f"Expected SABnzbd download client, found {clients_list[0]['name']}"
      assert clients_list[0]['implementationName'] == 'SABnzbd', \
          "Expected SABnzbd implementation"

      # Check that the movieCategory is set to 'radarr'
      category_field = next((field for field in clients_list[0]['fields'] if field['name'] == 'movieCategory'), None)
      assert category_field is not None, "Expected movieCategory field in SABnzbd download client"
      assert category_field['value'] == 'radarr', \
          f"Expected movieCategory 'radarr', found '{category_field['value']}'"
      print("SABnzbd download client configured successfully with radarr category!")

      # Check that default delay profile was created
      delay_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/delayprofile"
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

      machine.succeed("pgrep -u testuser Radarr")
    '';
  }
