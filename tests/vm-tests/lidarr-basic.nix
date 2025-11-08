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
    name = "lidarr-basic-test";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        lidarr = {
          enable = true;
          user = "testuser";
          mediaDirs = ["/media/music"];
          config = {
            hostConfig = {
              port = 8686;
              username = "admin";
              passwordPath = "${pkgs.writeText "lidarr-password" "testpassword123"}";
            };
            apiKeyPath = "${pkgs.writeText "lidarr-apikey" "5678efgh5678efgh5678efgh5678efgh"}";
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
          apiKeyPath = "${pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555"}";
          nzbKeyPath = "${pkgs.writeText "sabnzbd-nzbkey" "sabnzbdnzb666666666666666666666"}";
          settings = {
            port = 8080;
            host = "127.0.0.1";
            url_base = "/sabnzbd";
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for services to start
      machine.wait_for_unit("lidarr.service", timeout=60)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(8686, timeout=60)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("sabnzbd-config.service", timeout=60)
      machine.wait_for_unit("lidarr-config.service", timeout=180)

      # Wait for lidarr to come back up after restart
      machine.wait_for_unit("lidarr.service", timeout=60)
      machine.wait_for_open_port(8686, timeout=60)

      # Test API connectivity
      machine.succeed(
          "curl -f -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
          "http://127.0.0.1:8686/api/v1/system/status"
      )

      # Wait for root folders, delay profiles, and download clients services
      machine.wait_for_unit("lidarr-rootfolders.service", timeout=60)
      machine.wait_for_unit("lidarr-delayprofiles.service", timeout=60)
      machine.wait_for_unit("lidarr-downloadclients.service", timeout=60)

      # Check root folder
      folders = machine.succeed(
          "curl -s -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
          "http://127.0.0.1:8686/api/v1/rootfolder"
      )
      print(f"Root folders: {folders}")
      assert "/media/music" in folders, "Root folder not created"

      # Check that SABnzbd download client was configured
      import json
      clients = machine.succeed(
          "curl -s -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
          "http://127.0.0.1:8686/api/v1/downloadclient"
      )
      clients_list = json.loads(clients)
      print(f"Download clients: {clients}")
      assert len(clients_list) == 1, f"Expected 1 download client, found {len(clients_list)}"
      assert clients_list[0]['name'] == 'SABnzbd', \
          f"Expected SABnzbd download client, found {clients_list[0]['name']}"
      assert clients_list[0]['implementationName'] == 'SABnzbd', \
          "Expected SABnzbd implementation"
      print("SABnzbd download client configured successfully!")

      # Check that default delay profile was created
      delay_profiles = machine.succeed(
          "curl -s -H 'X-Api-Key: 5678efgh5678efgh5678efgh5678efgh' "
          "http://127.0.0.1:8686/api/v1/delayprofile"
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

      machine.succeed("pgrep -u testuser dotnet")
    '';
  }
