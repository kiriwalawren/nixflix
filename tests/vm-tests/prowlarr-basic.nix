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
    name = "prowlarr-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        prowlarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 9696;
              username = "admin";
              password = {_secret = pkgs.writeText "prowlarr-password" "testpassword123";};
            };
            apiKey = {_secret = pkgs.writeText "prowlarr-apikey" "fedcba9876543210fedcba9876543210";};
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
      machine.wait_for_unit("prowlarr.service", timeout=180)
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(9696, timeout=180)
      machine.wait_for_open_port(8080, timeout=60)

      # Wait for configuration services to complete
      machine.wait_for_unit("prowlarr-config.service", timeout=180)

      # Wait for prowlarr to come back up after restart
      machine.wait_for_unit("prowlarr.service", timeout=60)
      machine.wait_for_open_port(9696, timeout=60)

      # Test API connectivity
      machine.succeed(
          "curl -f -H 'X-Api-Key: fedcba9876543210fedcba9876543210' "
          "http://127.0.0.1:9696/api/v1/system/status"
      )

      # Wait for download clients service
      machine.wait_for_unit("prowlarr-downloadclients.service", timeout=60)

      # Check that SABnzbd download client was configured
      import json
      clients = machine.succeed(
          "curl -s -H 'X-Api-Key: fedcba9876543210fedcba9876543210' "
          "http://127.0.0.1:9696/api/v1/downloadclient"
      )
      clients_list = json.loads(clients)
      print(f"Download clients: {clients}")
      assert len(clients_list) == 1, f"Expected 1 download client, found {len(clients_list)}"
      assert clients_list[0]['name'] == 'SABnzbd', \
          f"Expected SABnzbd download client, found {clients_list[0]['name']}"
      assert clients_list[0]['implementationName'] == 'SABnzbd', \
          "Expected SABnzbd implementation"
      print("SABnzbd download client configured successfully!")

      # Verify the service is running
      machine.succeed("pgrep Prowlarr")

      print("Prowlarr is running successfully!")
    '';
  }
