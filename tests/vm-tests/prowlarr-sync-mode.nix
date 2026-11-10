{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  apiKey = "fedcba9876543210fedcba9876543210";
in
pkgs.testers.runNixOSTest {
  name = "prowlarr-sync-mode";

  nodes.machine = {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 2048;
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];

    # Base configuration: the default sync mode, "delete".
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
          apiKey._secret = pkgs.writeText "prowlarr-apikey" apiKey;
        };
      };
    };

    specialisation = {
      refuse.configuration.nixflix.syncMode = "refuse";
      keep.configuration.nixflix.syncMode = "keep";
    };
  };

  testScript = ''
    import json
    import shlex

    BASE = "http://127.0.0.1:9696/api/v1"
    UNITS = ["prowlarr-indexers", "prowlarr-indexer-proxies", "prowlarr-applications"]
    # API collection -> name of the object injected behind nixflix's back
    INJECTED = {
        "indexer": "Injected Indexer",
        "indexerProxy": "Injected Proxy",
        "applications": "Injected App",
    }

    def api(path, method="GET", body=None):
        data = ""
        if body is not None:
            data = " -H 'Content-Type: application/json' --data-binary " + shlex.quote(json.dumps(body))
        out = machine.succeed(
            f"curl -sSf -X {method} -H 'X-Api-Key: ${apiKey}'{data} '{BASE}/{path}'"
        )
        return json.loads(out) if out.strip() else None

    def set_fields(obj, values):
        for field in obj["fields"]:
            if field["name"] in values:
                field["value"] = values[field["name"]]
        return obj

    def names(collection):
        return {o["name"] for o in api(collection)}

    def assert_injected(present):
        for collection, name in INJECTED.items():
            found = name in names(collection)
            assert found == present, f"{collection}: expected {name!r} present={present}, got {names(collection)}"

    def show(unit, prop):
        return machine.succeed(f"systemctl show -p {prop} --value {unit}").strip()

    def switch(toplevel):
        # The refuse configuration fails units on purpose, so switching may exit non-zero.
        machine.execute(f"{toplevel}/bin/switch-to-configuration test")
        for unit in UNITS:
            machine.succeed(f"systemctl reset-failed {unit} || true")

    start_all()
    machine.wait_for_unit("prowlarr.service", timeout=180)
    machine.wait_for_open_port(9696, timeout=180)
    for unit in UNITS:
        machine.wait_for_unit(f"{unit}.service", timeout=180)

    with subtest("inject undeclared objects"):
        proxy = next(s for s in api("indexerProxy/schema") if s["implementationName"] == "Http")
        proxy["name"] = INJECTED["indexerProxy"]
        set_fields(proxy, {"host": "127.0.0.1", "port": 3128})
        api("indexerProxy?forceSave=true", "POST", proxy)

        indexer = next(s for s in api("indexer/schema") if s["name"] == "Generic Newznab")
        indexer["name"] = INJECTED["indexer"]
        indexer["appProfileId"] = 1
        # Prowlarr connection-tests enabled indexers even with forceSave, and there is no network.
        indexer["enable"] = False
        set_fields(indexer, {"baseUrl": "http://127.0.0.1:1", "apiPath": "/api", "apiKey": "x"})
        api("indexer?forceSave=true", "POST", indexer)

        app = next(s for s in api("applications/schema") if s["implementationName"] == "Sonarr")
        app["name"] = INJECTED["applications"]
        app["syncLevel"] = "disabled"
        set_fields(app, {
            "prowlarrUrl": "http://127.0.0.1:9696",
            "baseUrl": "http://127.0.0.1:1",
            "apiKey": "0123456789abcdef0123456789abcdef",
        })
        api("applications?forceSave=true", "POST", app)

        assert_injected(True)

    with subtest("refuse: units exit 78, do not restart, change nothing"):
        switch("/run/booted-system/specialisation/refuse")
        for unit in UNITS:
            machine.fail(f"systemctl restart {unit}.service")
            assert show(unit, "ExecMainStatus") == "78", f"{unit}: {show(unit, 'ExecMainStatus')}"
            assert show(unit, "ActiveState") == "failed", f"{unit} is {show(unit, 'ActiveState')}"
        assert show("prowlarr-indexer-proxies", "RestartPreventExitStatus") == "78"
        # Past RestartSec=30: Restart=on-failure must not have rerun the refusal.
        machine.sleep(35)
        assert show("prowlarr-indexer-proxies", "NRestarts") == "0", show("prowlarr-indexer-proxies", "NRestarts")
        machine.succeed(
            "journalctl -u prowlarr-indexers.service | grep -F 'nixflix:   - Injected Indexer (id '"
        )
        assert_injected(True)

    with subtest("keep: units succeed and leave undeclared objects alone"):
        switch("/run/booted-system/specialisation/keep")
        for unit in UNITS:
            machine.succeed(f"systemctl restart {unit}.service")
        machine.succeed(
            "journalctl -u prowlarr-indexer-proxies.service | grep -F 'keeping 1 undeclared indexer proxies'"
        )
        assert_injected(True)

    with subtest("delete (default): undeclared objects are removed"):
        switch("/run/booted-system")
        for unit in UNITS:
            machine.succeed(f"systemctl restart {unit}.service")
        assert_injected(False)
  '';
}
