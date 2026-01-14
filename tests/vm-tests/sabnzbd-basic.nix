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
          settings = {
            api_key = {_secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";};
            nzb_key = {_secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";};
            port = 8080;
            host = "127.0.0.1";
            url_base = "/sabnzbd";
            ignore_samples = true;
            direct_unpack = true;
            article_tries = 5;
            cache_limit = "512M";
            servers = [
              {
                name = "TestServer";
                host = "news.example.com";
                port = 563;
                username = {_secret = pkgs.writeText "eweka-username" "testuser";};
                password = {_secret = pkgs.writeText "eweka-password" "testpass123";};
                connections = 10;
                ssl = true;
                priority = 0;
                retention = 3000;
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

      # Verify the template file exists
      machine.succeed("test -f /etc/sabnzbd/sabnzbd.ini.template")

      # Check template contains placeholders (not actual secrets)
      template_content = machine.succeed("cat /etc/sabnzbd/sabnzbd.ini.template")
      print(f"Template content:\n{template_content}")
      assert "__SECRET_FILE__" in template_content, "Template should contain secret placeholders"
      assert "testapikey123456789abcdef" not in template_content, "Template should not contain actual secrets"

      # Verify the config file exists and has correct permissions
      machine.succeed("test -f /var/lib/sabnzbd/sabnzbd.ini")
      machine.succeed("stat -c '%U:%G' /var/lib/sabnzbd/sabnzbd.ini | grep -q 'sabnzbd:media'")
      machine.succeed("stat -c '%a' /var/lib/sabnzbd/sabnzbd.ini | grep -q '600'")

      # Check the journal output from the sabnzbd service
      sabnzbd_journal = machine.succeed("journalctl -u sabnzbd.service -n 50 --no-pager")
      print(f"SABnzbd service journal:\n{sabnzbd_journal}")

      # Verify the merged config file has actual secret values
      config_content = machine.succeed("cat /var/lib/sabnzbd/sabnzbd.ini")
      print(f"Config content:\n{config_content}")

      # Check that secrets were merged correctly
      assert "testapikey123456789abcdef" in config_content, "API key not merged"
      assert "testnzbkey123456789abcdef" in config_content, "NZB key not merged"
      assert "__SECRET_FILE__" not in config_content, "Secret placeholders not replaced"

      # Verify misc section settings
      assert "[misc]" in config_content, "Misc section missing"
      assert "host = 127.0.0.1" in config_content, "Host not set correctly"
      assert "port = 8080" in config_content, "Port not set correctly"
      assert "url_base = /sabnzbd" in config_content, "URL base not set correctly"
      assert "direct_unpack = 1" in config_content, "Direct unpack not set"
      assert "article_tries = 5" in config_content, "Article tries not set"
      assert "cache_limit = 512M" in config_content, "Cache limit not set"

      # Verify server configuration from INI
      assert "[servers]" in config_content, "Servers section missing"
      assert "[[TestServer]]" in config_content, "TestServer not found"
      assert "host = news.example.com" in config_content, "Server host not set"
      assert "port = 563" in config_content, "Server port not set"
      assert "testuser" in config_content, "Username not set"
      assert "testpass123" in config_content, "Password not set"
      assert "connections = 10" in config_content, "Server connections not set"
      assert "ssl = 1" in config_content, "SSL not enabled"
      assert "priority = 0" in config_content, "Server priority not set"
      assert "retention = 3000" in config_content, "Retention (freeform) not set"

      # Verify categories were configured via INI
      assert "[categories]" in config_content, "Categories section missing"
      assert "[[tv]]" in config_content, "TV category missing"
      assert "[[movies]]" in config_content, "Movies category missing"
      assert "dir = tv" in config_content, "TV category dir not set"
      assert "pp = 3" in config_content, "TV post-processing not set"
      assert "priority = 1" in config_content, "Movies priority not set"
      assert "pp = 2" in config_content, "Movies post-processing not set"

      # Verify no API config service exists (removed)
      machine.fail("systemctl status sabnzbd-config.service")
    '';
  }
