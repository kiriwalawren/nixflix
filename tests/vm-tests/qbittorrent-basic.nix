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
  name = "qbittorrent-basic-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ nixosModules ];

      virtualisation.cores = 4;

      environment.systemPackages = with pkgs; [
        jq
        curl
      ];

      nixflix = {
        enable = true;

        torrentClients.qbittorrent = {
          enable = true;
          webuiPort = 8282;
          password = "test123";
          downloadsDir = "/downloads/torrent";

          categories = {
            movies = "/downloads/torrent/movies";
            tv = "/downloads/torrent/tv";
          };

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
    start_all()

    # Wait for qBittorrent to start
    machine.wait_for_unit("qbittorrent.service", timeout=60)
    machine.wait_for_open_port(8282, timeout=60)

    # Verify the service is running under the correct user
    machine.succeed("pgrep -u qbittorrent")

    # Verify categories file was created with correct content
    machine.succeed("test -f /var/lib/qBittorrent/qBittorrent/config/categories.json")
    categories = machine.succeed("cat /var/lib/qBittorrent/qBittorrent/config/categories.json")
    print(f"Categories content:\n{categories}")

    import json
    parsed = json.loads(categories)
    assert "movies" in parsed, "movies category missing"
    assert parsed["movies"]["save_path"] == "/downloads/torrent/movies", "movies save_path incorrect"
    assert "tv" in parsed, "tv category missing"
    assert parsed["tv"]["save_path"] == "/downloads/torrent/tv", "tv save_path incorrect"

    # Verify WebUI is accessible
    machine.succeed("curl -f http://127.0.0.1:8282")
  '';
}
