{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "pinchflat-basic";

  nodes.machine = {
    imports = [ nixosModules ];

    virtualisation = {
      diskSize = 3 * 1024;
      memorySize = 4096;
      cores = 4;
    };

    nixflix = {
      enable = true;
      mediaDir = "/data/media";

      nginx = {
        enable = true;
        addHostsEntries = true;
      };

      pinchflat = {
        enable = true;
        selfhosted = true;
      };

      # Exercises the YouTube library: jellyfin-libraries `mkdir -p`s its path as root
      jellyfin = {
        enable = true;
        apiKey._secret = pkgs.writeText "jellyfin-apikey" "jellyfinApiKey1111111111111111111";
        users.admin = {
          password._secret = pkgs.writeText "admin_password" "321password";
          policy.isAdministrator = true;
        };
      };
    };
  };

  testScript = ''
    start_all()

    port = 8945
    machine.wait_for_unit("pinchflat.service", timeout=300)
    machine.wait_for_open_port(port, timeout=300)

    print("Checking Pinchflat answers HTTP on its port...")
    machine.succeed(f"curl -sf http://127.0.0.1:{port}/healthcheck")
    machine.succeed(f"curl -sf http://127.0.0.1:{port}/ | grep -qi pinchflat")

    print("Checking the media directory ownership...")
    owner = machine.succeed("stat -c '%U:%G %a' /data/media/youtube").strip()
    assert owner == "root:media 775", f"Expected /data/media/youtube to be root:media 775, got {owner}"

    print("Checking the service user and group...")
    unit_user = machine.succeed("systemctl show pinchflat.service -p User --value").strip()
    unit_group = machine.succeed("systemctl show pinchflat.service -p Group --value").strip()
    assert unit_user == "pinchflat", f"Expected User=pinchflat, got {unit_user}"
    assert unit_group == "media", f"Expected Group=media, got {unit_group}"
    machine.succeed("id -nG pinchflat | grep -qw media")

    print("Checking the unit UMask keeps downloads group-writable...")
    umask = machine.succeed("systemctl show pinchflat.service -p UMask --value").strip()
    assert umask == "0002", f"Expected UMask=0002, got {umask}"

    print("Checking the media directory is writable by the service user...")
    machine.succeed("runuser -u pinchflat -- touch /data/media/youtube/.write-test")

    print("Checking the Media Center /shows folder ownership...")
    shows_owner = machine.succeed("stat -c '%U:%G %a' /data/media/youtube/shows").strip()
    assert shows_owner == "root:media 775", f"Expected /data/media/youtube/shows to be root:media 775, got {shows_owner}"
    machine.succeed("runuser -u pinchflat -- mkdir -p '/data/media/youtube/shows/Some Channel/Season 2026'")

    print("Checking the Jellyfin YouTube library points at /shows...")
    machine.wait_for_unit("jellyfin-libraries.service", timeout=600)
    machine.succeed("systemctl is-active jellyfin-libraries.service")
    import json
    api_token = machine.succeed("cat /run/jellyfin/auth-token").strip()
    libraries = json.loads(machine.succeed(
        f'curl -sf -H "Authorization: {api_token}" http://127.0.0.1:8096/Library/VirtualFolders'
    ))
    youtube = [lib for lib in libraries if lib["Name"] == "YouTube"]
    assert len(youtube) == 1, f"Expected one YouTube library, got {libraries}"
    assert youtube[0]["Locations"] == ["/data/media/youtube/shows"], f"Unexpected YouTube locations: {youtube[0]['Locations']}"
    assert youtube[0]["CollectionType"] == "tvshows", f"Unexpected CollectionType: {youtube[0].get('CollectionType')}"
    shows_owner = machine.succeed("stat -c '%U:%G %a' /data/media/youtube/shows").strip()
    assert shows_owner == "root:media 775", f"jellyfin-libraries changed /shows to {shows_owner}"

    print("Checking Pinchflat via the reverse proxy...")
    machine.wait_for_unit("nginx.service", timeout=120)
    machine.succeed("curl -sf http://pinchflat.nixflix/healthcheck")

    print("All Pinchflat assertions passed!")
  '';
}
