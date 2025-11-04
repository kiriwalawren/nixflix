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
    name = "sonarr-basic-test";

    nodes.machine = {
      config,
      pkgs,
      ...
    }: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        sonarr = {
          enable = true;
          user = "testuser";
          mediaDirs = [
            {dir = "/media/tv";}
          ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              passwordPath = "${pkgs.writeText "sonarr-password" "testpassword123"}";
            };
            apiKeyPath = "${pkgs.writeText "sonarr-apikey" "0123456789abcdef0123456789abcdef"}";
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
      machine.wait_for_unit("sonarr.service", timeout=60)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(8989, timeout=60)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("sabnzbd-config.service", timeout=60)
      machine.wait_for_unit("sonarr-config.service", timeout=180)

      # Wait for sonarr to come back up after restart
      machine.wait_for_unit("sonarr.service", timeout=60)
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

      # Wait for root folders and download clients services
      machine.wait_for_unit("sonarr-rootfolders.service", timeout=60)
      machine.wait_for_unit("sonarr-downloadclients.service", timeout=60)

      # Check that root folder was created
      folders = machine.succeed(
          "curl -s -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
          "http://127.0.0.1:8989/api/v3/rootfolder"
      )
      print(f"Root folders: {folders}")
      assert "/media/tv" in folders, "Root folder not created"

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
      print("SABnzbd download client configured successfully!")

      # Verify the service is running under the correct user
      machine.succeed("pgrep -u testuser Sonarr")
    '';
  }
