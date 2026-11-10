{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  apiKey = "syncmode1234abcd1234abcd1234abcd";
  injectedFolder = "/media/injected";
in
pkgs.testers.runNixOSTest {
  name = "radarr-sync-mode";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ nixosModules ];

    virtualisation.cores = 4;

    # Radarr only accepts a root folder that exists and that it can write to.
    systemd.tmpfiles.settings."10-radarr-sync-mode-test".${injectedFolder}.d = {
      inherit (config.nixflix.globals.libraryOwner) user group;
      mode = "0775";
    };

    nixflix = {
      enable = true;

      radarr = {
        enable = true;
        mediaDirs = [ "/media/movies" ];
        config = {
          hostConfig = {
            port = 7878;
            username = "admin";
            password._secret = pkgs.writeText "radarr-password" "testpassword123";
          };
          apiKey._secret = pkgs.writeText "radarr-apikey" apiKey;
        };
      };
    };

    specialisation = {
      refuse.configuration.nixflix.radarr.syncMode = {
        rootFolders = "refuse";
        delayProfiles = "refuse";
      };
      keep.configuration.nixflix.radarr.syncMode = {
        rootFolders = "keep";
        delayProfiles = "keep";
      };
    };
  };

  testScript = ''
    import json

    BASE = "http://127.0.0.1:7878/api/v3"
    HDR = "-H 'X-Api-Key: ${apiKey}'"
    UNITS = ["radarr-rootfolders.service", "radarr-delayprofiles.service"]

    def api(path, method="GET", body=None):
        data = f" -H 'Content-Type: application/json' --data-binary '{json.dumps(body)}'" if body is not None else ""
        out = machine.succeed(f"curl -sf -X {method} {HDR}{data} '{BASE}/{path}'")
        return json.loads(out) if out.strip() else None

    def folder_paths():
        return sorted(f["path"].rstrip("/") for f in api("rootfolder"))

    def profile_ids():
        return sorted(p["id"] for p in api("delayprofile"))

    def switch(cmd):
        return machine.execute(f"{cmd} test 2>&1")

    def main_status(unit):
        return machine.succeed(f"systemctl show -p ExecMainStatus --value {unit}").strip()

    start_all()
    machine.wait_for_unit("radarr.service", timeout=180)
    machine.wait_for_open_port(7878, timeout=180)
    for unit in UNITS:
        machine.wait_for_unit(unit, timeout=180)

    assert folder_paths() == ["/media/movies"], folder_paths()
    assert profile_ids() == [1], profile_ids()

    # Objects created outside nixflix.
    tag = api("tag", "POST", {"label": "injected"})
    api("rootfolder?forceSave=true", "POST", {"path": "${injectedFolder}"})
    injected_profile = api("delayprofile?forceSave=true", "POST", {
        "enableUsenet": True, "enableTorrent": True, "preferredProtocol": "usenet",
        "usenetDelay": 30, "torrentDelay": 30, "bypassIfHighestQuality": False,
        "bypassIfAboveCustomFormatScore": False, "minimumCustomFormatScore": 0,
        "order": 1, "tags": [tag["id"]],
    })
    pid = injected_profile["id"]
    assert folder_paths() == sorted(["/media/movies", "${injectedFolder}"]), folder_paths()
    assert profile_ids() == [1, pid], profile_ids()

    with subtest("refuse: the units fail with 78 and change nothing"):
        rc, out = switch("/run/booted-system/specialisation/refuse/bin/switch-to-configuration")
        print(out)
        assert rc != 0, "switching to refuse should report the failed units"
        for unit in UNITS:
            machine.wait_until_fails(f"systemctl is-active {unit}", timeout=60)
            assert main_status(unit) == "78", f"{unit}: ExecMainStatus {main_status(unit)}"
        journal = machine.succeed("journalctl -o cat -u radarr-rootfolders.service -u radarr-delayprofiles.service")
        assert "nixflix:   - ${injectedFolder} (id " in journal, journal
        assert f"nixflix:   - {pid} (id {pid})" in journal, journal
        assert "Nothing was changed." in journal, journal
        assert "${apiKey}" not in journal, "API key leaked into the journal"
        assert folder_paths() == sorted(["/media/movies", "${injectedFolder}"]), folder_paths()
        assert profile_ids() == [1, pid], profile_ids()

    with subtest("keep: the units succeed and keep the undeclared objects"):
        rc, out = switch("/run/booted-system/specialisation/keep/bin/switch-to-configuration")
        print(out)
        assert rc == 0, "switching to keep failed"
        for unit in UNITS:
            machine.wait_for_unit(unit, timeout=60)
        journal = machine.succeed("journalctl -o cat -u radarr-rootfolders.service -u radarr-delayprofiles.service")
        assert 'keeping 1 undeclared root folders (nixflix.radarr.syncMode.rootFolders = "keep"): ${injectedFolder}' in journal, journal
        assert f'keeping 1 undeclared delay profiles (nixflix.radarr.syncMode.delayProfiles = "keep"): {pid}' in journal, journal
        assert folder_paths() == sorted(["/media/movies", "${injectedFolder}"]), folder_paths()
        assert profile_ids() == [1, pid], profile_ids()

    with subtest("delete (the default): the undeclared objects are removed"):
        rc, out = switch("/run/booted-system/bin/switch-to-configuration")
        print(out)
        assert rc == 0, "switching back to the default failed"
        for unit in UNITS:
            machine.wait_for_unit(unit, timeout=60)
        assert folder_paths() == ["/media/movies"], folder_paths()
        assert profile_ids() == [1], profile_ids()
  '';
}
