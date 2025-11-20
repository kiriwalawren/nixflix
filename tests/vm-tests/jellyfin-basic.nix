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
    name = "jellyfin-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      virtualisation = {
        diskSize = 4096; # 4GB disk to satisfy Jellyfin's 2GB minimum requirement
        memorySize = 2048; # 2GB RAM for better performance
      };

      nixflix = {
        enable = true;

        jellyfin = {
          enable = true;
          user = "jellyfin";

          network = {
            internalHttpPort = 8096;
            baseUrl = "/jellyfin";
            enableRemoteAccess = true;
          };

          system = {
            serverName = "Test Jellyfin Server";
            UICulture = "en-US";
            metadataCountryCode = "US";
            preferredMetadataLanguage = "en";
          };

          branding = {
            loginDisclaimer = "Test Server";
          };

          users = {
            admin = {
              passwordFile = pkgs.writeText "admin-password" "testpassword123";
              policy = {
                isAdministrator = true;
                isHidden = false;
              };
            };
            testuser = {
              passwordFile = pkgs.writeText "testuser-password" "userpassword456";
              policy = {
                isAdministrator = false;
                isHidden = false;
                enableMediaPlayback = true;
                enableContentDownloading = true;
              };
            };
          };

          apikeys = {
            default = pkgs.writeText "jellyfin-default-apikey" "0123456789abcdef0123456789abcdef";
            testapp = pkgs.writeText "jellyfin-testapp-apikey" "fedcba9876543210fedcba9876543210";
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for main Jellyfin service to start
      machine.wait_for_unit("jellyfin.service", timeout=120)
      machine.wait_for_open_port(8096, timeout=60)

      # Wait for initialization service to complete
      machine.wait_for_unit("jellyfin-initialization.service", timeout=300)
      print("Jellyfin initialization completed")

      # Wait for setup wizard service to complete
      machine.wait_for_unit("jellyfin-setup-wizard.service", timeout=180)
      print("Jellyfin setup wizard completed")

      # Wait for API keys service to complete
      machine.wait_for_unit("jellyfin-api-keys.service", timeout=60)
      print("Jellyfin API keys configured")

      # Wait for system configuration service to complete
      machine.wait_for_unit("jellyfin-system-config.service", timeout=120)
      print("Jellyfin system configuration completed")

      # Wait for users configuration service to complete
      machine.wait_for_unit("jellyfin-users-config.service", timeout=120)
      print("Jellyfin users configuration completed")

      # Test basic API connectivity
      machine.succeed(
          "curl -f http://127.0.0.1:8096/jellyfin/System/Ping"
      )
      print("API ping successful")

      # Test API with API key authentication
      result = machine.succeed(
          "curl -s -f -H 'Authorization: MediaBrowser Token=\"0123456789abcdef0123456789abcdef\"' "
          "http://127.0.0.1:8096/jellyfin/System/Info"
      )
      print(f"System info: {result}")
      assert "ServerName" in result, "System info missing ServerName"
      assert "Test Jellyfin Server" in result, "Server name not configured correctly"

      # Verify users were created
      import json

      # Authenticate as admin to get access token
      auth_response = machine.succeed(
          "curl -s -X POST "
          "-H 'Content-Type: application/json' "
          "-H 'Authorization: MediaBrowser Client=\"nixflix-test\", Device=\"NixOS\", DeviceId=\"test\", Version=\"1.0.0\"' "
          "-d '{\"Username\": \"admin\", \"Pw\": \"testpassword123\"}' "
          "http://127.0.0.1:8096/jellyfin/Users/AuthenticateByName"
      )
      print(f"Admin auth response: {auth_response}")
      auth_data = json.loads(auth_response)
      assert "AccessToken" in auth_data, "Failed to authenticate as admin"
      access_token = auth_data["AccessToken"]
      print("Admin authenticated successfully with token")

      # Fetch users list
      users_response = machine.succeed(
          f"curl -s -H 'Authorization: MediaBrowser Client=\"nixflix-test\", Device=\"NixOS\", DeviceId=\"test\", Version=\"1.0.0\", Token=\"{access_token}\"' "
          "http://127.0.0.1:8096/jellyfin/Users"
      )
      print(f"Users response: {users_response}")
      users = json.loads(users_response)

      # Verify both users exist
      assert len(users) == 2, f"Expected 2 users, found {len(users)}"

      user_names = [user["Name"] for user in users]
      assert "admin" in user_names, "Admin user not found"
      assert "testuser" in user_names, "Test user not found"
      print("Both users created successfully")

      # Verify admin user properties
      admin_user = [user for user in users if user["Name"] == "admin"][0]
      assert admin_user["Policy"]["IsAdministrator"] == True, "Admin user is not an administrator"
      assert admin_user["Policy"]["IsHidden"] == False, "Admin user should not be hidden"
      print("Admin user configured correctly")

      # Verify test user properties
      test_user = [user for user in users if user["Name"] == "testuser"][0]
      assert test_user["Policy"]["IsAdministrator"] == False, "Test user should not be an administrator"
      assert test_user["Policy"]["IsHidden"] == False, "Test user should not be hidden"
      assert test_user["Policy"]["EnableMediaPlayback"] == True, "Test user should have media playback enabled"
      assert test_user["Policy"]["EnableContentDownloading"] == True, "Test user should have content downloading enabled"
      print("Test user configured correctly")

      # Verify API keys were created in the database
      api_keys_check = machine.succeed(
          "${pkgs.sqlite}/bin/sqlite3 /var/lib/jellyfin/data/jellyfin.db "
          "\"SELECT COUNT(*) FROM ApiKeys WHERE Name IN ('default', 'testapp')\""
      )
      api_key_count = int(api_keys_check.strip())
      assert api_key_count == 2, f"Expected 2 API keys, found {api_key_count}"
      print("API keys configured in database")

      # Test authentication with testuser
      testuser_auth = machine.succeed(
          "curl -s -X POST "
          "-H 'Content-Type: application/json' "
          "-H 'Authorization: MediaBrowser Client=\"nixflix-test\", Device=\"NixOS\", DeviceId=\"test2\", Version=\"1.0.0\"' "
          "-d '{\"Username\": \"testuser\", \"Pw\": \"userpassword456\"}' "
          "http://127.0.0.1:8096/jellyfin/Users/AuthenticateByName"
      )
      print(f"Testuser auth response: {testuser_auth}")
      testuser_data = json.loads(testuser_auth)
      assert "AccessToken" in testuser_data, "Failed to authenticate as testuser"
      print("Testuser authenticated successfully")

      # Verify the service is running under the correct user
      machine.succeed("pgrep -u jellyfin jellyfin")
      print("Jellyfin running under correct user")

      # Verify configuration files exist
      machine.succeed("test -f /var/lib/jellyfin/config/network.xml")
      machine.succeed("test -f /var/lib/jellyfin/config/branding.xml")
      machine.succeed("test -f /var/lib/jellyfin/config/encoding.xml")
      machine.succeed("test -f /var/lib/jellyfin/config/system.xml")
      print("Configuration files created successfully")

      # Verify system.xml contains IsStartupWizardCompleted=true
      system_xml = machine.succeed("cat /var/lib/jellyfin/config/system.xml")
      assert "<IsStartupWizardCompleted>true</IsStartupWizardCompleted>" in system_xml, \
          "Setup wizard not marked as completed"
      print("Setup wizard marked as completed")

      print("All tests passed!")
    '';
  }
