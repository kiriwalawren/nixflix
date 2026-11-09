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
      diskSize = 2 * 1024;
      memorySize = 2048;
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

    print("Checking Pinchflat via the reverse proxy...")
    machine.wait_for_unit("nginx.service", timeout=120)
    machine.succeed("curl -sf http://pinchflat.nixflix/healthcheck")

    print("All Pinchflat assertions passed!")
  '';
}
