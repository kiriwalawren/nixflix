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
    name = "sabnzbd-basic-test";

    nodes.machine = {pkgs, ...}: {
      imports = [nixosModules];

      nixflix = {
        enable = true;

        sabnzbd = {
          enable = true;
          downloadsDir = "/downloads/usenet";
          apiKeyPath = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
          nzbKeyPath = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
          environmentSecrets = [
            {
              env = "EWEKA_USERNAME";
              path = pkgs.writeText "eweka-username" "testuser";
            }
            {
              env = "EWEKA_PASSWORD";
              path = pkgs.writeText "eweka-password" "testpass123";
            }
          ];
          settings = {
            port = 8080;
            host = "127.0.0.1";
            url_base = "/sabnzbd";
            ignore_samples = true;
            direct_unpack = true;
            article_tries = 5;
            servers = [
              {
                name = "TestServer";
                host = "news.example.com";
                port = 563;
                username = "$EWEKA_USERNAME";
                password = "$EWEKA_PASSWORD";
                connections = 10;
                ssl = true;
                priority = 0;
              }
            ];
            categories = [
              {
                name = "tv";
                dir = "tv";
                priority = 0;
                pp = 3;
                script = "None";
              }
              {
                name = "movies";
                dir = "movies";
                priority = 1;
                pp = 2;
                script = "None";
              }
            ];
          };
        };
      };
    };

    testScript = ''
      start_all()

      # Wait for SABnzbd to start
      machine.wait_for_unit("sabnzbd.service", timeout=60)
      machine.wait_for_open_port(8080, timeout=60)

      # Verify the service is running under the correct user
      machine.succeed("pgrep -u sabnzbd")

      # Verify directories were created with correct ownership
      machine.succeed("test -d /downloads/usenet")
      machine.succeed("test -d /downloads/usenet/incomplete")
      machine.succeed("test -d /downloads/usenet/complete")
      machine.succeed("stat -c '%U:%G' /downloads/usenet | grep -q 'sabnzbd:media'")

      # Check what files SABnzbd created
      state_dir_contents = machine.succeed("ls -la /var/lib/sabnzbd/")
      print(f"SABnzbd state directory contents:\n{state_dir_contents}")

      # Verify the config file exists and has correct permissions
      machine.succeed("test -f /var/lib/sabnzbd/sabnzbd.ini")
      machine.succeed("stat -c '%U:%G' /var/lib/sabnzbd/sabnzbd.ini | grep -q 'sabnzbd:media'")
      machine.succeed("stat -c '%a' /var/lib/sabnzbd/sabnzbd.ini | grep -q '600'")

      # Wait for API configuration service to complete
      machine.wait_for_unit("sabnzbd-config.service", timeout=120)

      # Check the journal output from the config service
      config_journal = machine.succeed("journalctl -u sabnzbd-config.service -n 50 --no-pager")
      print(f"SABnzbd config service journal:\n{config_journal}")

      # Verify the minimal config file has correct values
      config_content = machine.succeed("cat /var/lib/sabnzbd/sabnzbd.ini")
      print(f"Config content:\n{config_content}")

      # Check that environment variables were substituted in minimal config
      assert "testapikey123456789abcdef" in config_content, "API key not substituted"
      assert "$SABNZBD_API_KEY" not in config_content, "API key placeholder not replaced"
      assert "url_base = /sabnzbd" in config_content, "URL base not set correctly"

      # Verify API-configured values by checking the config file
      # (SABnzbd writes API changes back to the INI file)
      assert "testuser" in config_content, "Username not set via API"
      assert "testpass123" in config_content, "Password not set via API"

      # Verify server configuration was applied via API
      assert "[servers]" in config_content, "Servers section missing"
      assert "[[TestServer]]" in config_content, "TestServer not found"
      assert "host = news.example.com" in config_content, "Server host not set"
      assert "connections = 10" in config_content, "Server connections not set"

      # Verify categories were configured via API
      assert "[categories]" in config_content, "Categories section missing"
      assert "[[tv]]" in config_content, "TV category missing"
      assert "[[movies]]" in config_content, "Movies category missing"
      assert "dir = tv" in config_content or "dir=tv" in config_content, "TV category dir not set"
      assert "priority = 1" in config_content or "priority=1" in config_content, "Movies priority not set"
      assert "pp = 2" in config_content or "pp=2" in config_content, "Movies post-processing not set"
      assert "direct_unpack = 1" in config_content or "direct_unpack=1" in config_content, "Direct Unpack not set"
    '';
  }
