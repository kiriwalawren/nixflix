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

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      imports = [nixosModules];

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
              passwordPath = "${pkgs.writeText "radarr-password" "testpassword123"}";
            };
            apiKeyPath = "${pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234"}";
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
      machine.wait_for_unit("radarr.service", timeout=60)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(7878, timeout=60)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("sabnzbd-config.service", timeout=60)
      machine.wait_for_unit("radarr-config.service", timeout=180)

      # Wait for radarr to come back up after restart
      machine.wait_for_unit("radarr.service", timeout=60)
      machine.wait_for_open_port(7878, timeout=60)

      # Test API connectivity
      machine.succeed(
          "curl -f -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
          "http://127.0.0.1:7878/api/v3/system/status"
      )

      # Wait for root folders and download clients services
      machine.wait_for_unit("radarr-rootfolders.service", timeout=60)
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
      print("SABnzbd download client configured successfully!")

      machine.succeed("pgrep -u testuser Radarr")
    '';
  }
