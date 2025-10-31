{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
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
        mediaDirs = [
          {dir = "/media/movies";}
        ];
        config = {
          hostConfig = {
            port = 7878;
            username = "admin";
            passwordPath = "${pkgs.writeText "radarr-password" "testpassword123"}";
          };
          apiKeyPath = "${pkgs.writeText "radarr-apikey" "abcd1234abcd1234abcd1234abcd1234"}";
        };
      };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_open_port(7878, timeout=20)
    machine.wait_for_unit("radarr-config.service", timeout=20)

    # Wait for radarr to come back up after restart
    machine.wait_for_unit("radarr.service", timeout=20)
    machine.wait_for_open_port(7878, timeout=20)

    # Test API connectivity
    machine.succeed(
        "curl -f -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
        "http://127.0.0.1:7878/api/v3/system/status"
    )

    # Wait for root folders service
    machine.wait_for_unit("radarr-rootfolders.service", timeout=20)

    # Check root folder
    folders = machine.succeed(
        "curl -s -H 'X-Api-Key: abcd1234abcd1234abcd1234abcd1234' "
        "http://127.0.0.1:7878/api/v3/rootfolder"
    )
    print(f"Root folders: {folders}")
    assert "/media/movies" in folders, "Root folder not created"

    machine.succeed("pgrep -u testuser Radarr")
  '';
}
