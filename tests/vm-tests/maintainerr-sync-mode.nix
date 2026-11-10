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
  maintainerr = "http://127.0.0.1:6246/api";
in
# nixflix.maintainerr.syncMode.mediaServer = "refuse" against a real
# Maintainerr: a fresh install switches to Jellyfin through the preview
# endpoint; a Maintainerr moved to Plex with rule groups kept is refused,
# and nothing is switched or cleared.
pkgsUnfree.testers.runNixOSTest {
  name = "maintainerr-sync-mode";

  nodes.machine = { ... }: {
    imports = [ nixosModules ];

    virtualisation = {
      diskSize = 3 * 1024;
      memorySize = 4096;
      cores = 4;
    };

    environment.systemPackages = [ pkgs.jq ];

    nixflix = {
      enable = true;
      syncMode = "refuse";

      jellyfin = {
        enable = true;
        apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";
        users.admin = {
          password._secret = pkgs.writeText "admin-password" "321password";
          policy.isAdministrator = true;
        };
        libraries.Movies = {
          collectionType = "movies";
          paths = [ "/media/movies" ];
        };
      };

      maintainerr = {
        enable = true;
        rules = [
          {
            name = "Old movies";
            library = "Movies";
            dataType = "movie";
          }
        ];
      };
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("jellyfin-libraries.service", timeout=600)
    machine.wait_for_unit("maintainerr.service", timeout=300)
    machine.wait_for_open_port(6246, timeout=300)

    # Fresh install: nothing to clear, so refuse switches to Jellyfin.
    # maintainerr-settings can start before Jellyfin has its admin user (it is
    # only ordered after jellyfin-api-key), so retry it once that exists.
    machine.wait_until_succeeds("journalctl -o cat -u maintainerr-settings.service | grep -qx 'Switching media server type to Jellyfin...'", timeout=300)
    machine.wait_for_unit("jellyfin-users-config.service", timeout=300)
    machine.wait_until_succeeds("systemctl restart maintainerr-settings.service", timeout=300)
    machine.succeed("curl -fsS ${maintainerr}/settings | jq -e '.media_server_type == \"jellyfin\"'")
    machine.succeed("curl -fsS ${maintainerr}/settings/media-server/switch/preview/plex | jq -e '.dataToBeCleared | type == \"object\" and (.collections | type == \"number\")'")

    # It requires maintainerr-settings, so its first start was skipped.
    machine.succeed("systemctl restart maintainerr-rules.service")
    machine.succeed("curl -fsS ${maintainerr}/rules | jq -e 'length == 1'")

    # Move it to Plex keeping the rule group, as an install that was on Plex.
    machine.succeed(
        "curl -fsS -X POST -H 'Content-Type: application/json' "
        + "-d '{\"targetServerType\":\"plex\",\"migrateRules\":true}' "
        + "${maintainerr}/settings/media-server/switch | jq -e '.status == \"OK\"'"
    )
    machine.succeed("curl -fsS ${maintainerr}/settings | jq -e '.media_server_type == \"plex\"'")
    machine.succeed("curl -fsS ${maintainerr}/rules | jq -e 'length == 1'")

    # refuse: exit 78, names what a switch clears, switches nothing.
    machine.fail("systemctl restart maintainerr-settings.service")
    machine.succeed("systemctl show -p ExecMainStatus maintainerr-settings.service | grep -qx ExecMainStatus=78")
    machine.succeed(
        "journalctl -o cat -u maintainerr-settings.service "
        + "| grep -F \"refusing to sync: Maintainerr uses media server 'plex', and switching it to Jellyfin clears 1 rule groups (with their rules)\""
    )
    machine.succeed("curl -fsS ${maintainerr}/settings | jq -e '.media_server_type == \"plex\"'")
    machine.succeed("curl -fsS ${maintainerr}/rules | jq -e 'length == 1'")
  '';
}
