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
  name = "downloadarr-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      virtualisation.cores = 4;

      nixflix = {
        enable = true;

        sonarr = {
          enable = true;
          mediaDirs = [ "/media/tv" ];
          config = {
            hostConfig = {
              port = 8989;
              username = "admin";
              password._secret = pkgs.writeText "sonarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "sonarr-apikey" "0123456789abcdef0123456789abcdef";
          };
        };

        radarr = {
          enable = true;
          mediaDirs = [ "/media/movies" ];
          config = {
            hostConfig = {
              port = 7878;
              username = "admin";
              password._secret = pkgs.writeText "radarr-password" "testpassword123";
            };
            apiKey._secret = pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234";
          };
        };

        torrentClients.qbittorrent = {
          enable = true;
          webuiPort = 8282;
          password = "test123";
          serverConfig = {
            LegalNotice.Accepted = true;
            Preferences.WebUI = {
              Username = "admin";
              LocalHostAuth = false;
              Locale = "en";
            };
          };
        };
      };
    };

  testScript = ''
    import json

    start_all()

    SONARR_KEY = "0123456789abcdef0123456789abcdef"
    RADARR_KEY = "abcd1234abcd1234abcd1234abcd1234"

    # Wait for services to start (longer timeout for initial DB migrations)
    machine.wait_for_unit("sonarr.service", timeout=180)
    machine.wait_for_unit("radarr.service", timeout=180)
    machine.wait_for_unit("qbittorrent.service", timeout=60)
    machine.wait_for_open_port(8989, timeout=180)
    machine.wait_for_open_port(7878, timeout=180)

    # Wait for the config services (which restart Sonarr/Radarr)
    machine.wait_for_unit("sonarr-config.service", timeout=180)
    machine.wait_for_unit("radarr-config.service", timeout=180)

    # Wait for Sonarr/Radarr to come back up after restart
    machine.wait_for_unit("sonarr.service", timeout=60)
    machine.wait_for_unit("radarr.service", timeout=60)
    machine.wait_for_open_port(8989, timeout=60)
    machine.wait_for_open_port(7878, timeout=60)

    # Downloadarr's reconciliation units - proves the SAME qBittorrent definition
    # gets applied to both services from one central place
    machine.wait_for_unit("sonarr-downloadclients.service", timeout=60)
    machine.wait_for_unit("radarr-downloadclients.service", timeout=60)

    def get_clients(port, api_key):
        raw = machine.succeed(
            f"curl -sf -H 'X-Api-Key: {api_key}' http://127.0.0.1:{port}/api/v3/downloadclient"
        )
        return json.loads(raw)

    sonarr_clients = get_clients(8989, SONARR_KEY)
    print(f"Sonarr download clients: {sonarr_clients}")
    assert len(sonarr_clients) == 1, f"Expected 1 download client on Sonarr, found {len(sonarr_clients)}"
    sonarr_qbit = sonarr_clients[0]
    assert sonarr_qbit["name"] == "qBittorrent", f"Expected name 'qBittorrent', got {sonarr_qbit.get('name')}"
    assert sonarr_qbit["implementationName"] == "qBittorrent", "Expected qBittorrent implementation"
    sonarr_category = next(f for f in sonarr_qbit["fields"] if f["name"] == "tvCategory")
    assert sonarr_category["value"] == "sonarr", f"Expected tvCategory 'sonarr', found {sonarr_category['value']}"

    radarr_clients = get_clients(7878, RADARR_KEY)
    print(f"Radarr download clients: {radarr_clients}")
    assert len(radarr_clients) == 1, f"Expected 1 download client on Radarr, found {len(radarr_clients)}"
    radarr_qbit = radarr_clients[0]
    assert radarr_qbit["name"] == "qBittorrent", f"Expected name 'qBittorrent', got {radarr_qbit.get('name')}"
    assert radarr_qbit["implementationName"] == "qBittorrent", "Expected qBittorrent implementation"
    radarr_category = next(f for f in radarr_qbit["fields"] if f["name"] == "movieCategory")
    assert radarr_category["value"] == "radarr", f"Expected movieCategory 'radarr', found {radarr_category['value']}"

    print("Downloadarr configured qBittorrent on both Sonarr and Radarr from a single definition!")
  '';
}
