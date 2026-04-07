{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };
in
pkgsUnfree.testers.runNixOSTest {
  name = "prowlarr-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      networking.useDHCP = true;
      virtualisation.cores = 4;

      nixflix = {
        enable = true;

        prowlarr = {
          enable = true;
          config = {
            hostConfig = {
              port = 9696;
              username = "admin";
              password._secret = pkgs.writeText "prowlarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "prowlarr-apikey" "fedcba9876543210fedcba9876543210";
          };
        };

        flaresolverr.enable = true;

        torrentClients.qbittorrent = {
          enable = true;
          webuiPort = 8282;
          password = "test123";
          serverConfig = {
            LegalNotice.Accepted = true;
            Preferences = {
              WebUI = {
                Username = "admin";
                Password_PBKDF2 = "@ByteArray(mLsFJ3Dsd3+uZt52Vu9FxA==:ON7uV17wWL0mlay5m5i7PYeBusWa7dgiH+eJG8wC/t+zihfqauUTS0q6DKTwsB5YtbOcmztixnuezjjApywXlw==)";
              };
              General.Locale = "en";
            };
          };
        };

        usenetClients.sabnzbd = {
          enable = true;
          settings = {
            misc = {
              api_key._secret = pkgs.writeText "sabnzbd-apikey" "sabnzbd555555555555555555555555555";
              nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "sabnzbdnzb666666666666666666666";
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
    machine.wait_for_open_port(8282, timeout=60)
    machine.wait_for_open_port(8191, timeout=60)

    # Wait for configuration services to complete
    machine.wait_for_unit("qbittorrent.service", timeout=180)
    machine.wait_for_unit("flaresolverr.service", timeout=180)
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
    assert len(clients_list) == 2, f"Expected 2 download client, found {len(clients_list)}"

    sabnzbd = next((c for c in clients_list if c["name"] == "SABnzbd"), None)
    assert sabnzbd is not None, \
        f"Expected SABnzbd download client, found {clients_list}"
    assert sabnzbd['implementationName'] == 'SABnzbd', \
        "Expected SABnzbd implementation"

    qbittorrent = next((c for c in clients_list if c["name"] == "qBittorrent"), None)
    assert qbittorrent is not None, \
        f"Expected qBittorrent download client, found {clients_list}"
    assert qbittorrent['implementationName'] == 'qBittorrent', \
        "Expected qBittorrent implementation"

    # Wait for tags and indexer proxies services
    machine.wait_for_unit("prowlarr-tags.service", timeout=60)
    machine.wait_for_unit("prowlarr-indexer-proxies.service", timeout=60)

    # Check that "flaresolverr" tag was created
    tags = machine.succeed(
        "curl -s -H 'X-Api-Key: fedcba9876543210fedcba9876543210' "
        "http://127.0.0.1:9696/api/v1/tag"
    )
    tags_list = json.loads(tags)
    print(f"Tags: {tags}")
    flaresolverr_tag = next((t for t in tags_list if t["label"] == "flaresolverr"), None)
    assert flaresolverr_tag is not None, \
        f"Expected 'flaresolverr' tag, found {tags_list}"

    # Check that FlareSolverr indexer proxy was created with correct host and tag
    proxies = machine.succeed(
        "curl -s -H 'X-Api-Key: fedcba9876543210fedcba9876543210' "
        "http://127.0.0.1:9696/api/v1/indexerProxy"
    )
    proxies_list = json.loads(proxies)
    print(f"Indexer proxies: {proxies}")
    flaresolverr_proxy = next((p for p in proxies_list if p["name"] == "FlareSolverr"), None)
    assert flaresolverr_proxy is not None, \
        f"Expected FlareSolverr indexer proxy, found {proxies_list}"

    # Verify host field contains the correct port (8191)
    host_field = next((f for f in flaresolverr_proxy["fields"] if f["name"] == "host"), None)
    assert host_field is not None, \
        f"Expected 'host' field in FlareSolverr proxy, found {flaresolverr_proxy['fields']}"
    assert host_field["value"] == "http://127.0.0.1:8191", \
        f"Expected host 'http://127.0.0.1:8191', got '{host_field['value']}'"

    # Verify the flaresolverr tag is assigned to the proxy
    assert flaresolverr_tag["id"] in flaresolverr_proxy["tags"], \
        f"Expected tag ID {flaresolverr_tag['id']} in proxy tags {flaresolverr_proxy['tags']}"

    # Verify the service is running
    machine.succeed("pgrep Prowlarr")

    print("Prowlarr is running successfully!")
  '';
}
