{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  apiKey = "jellyfinApiKey2222222222222222222";
  fixtures = "/var/lib/livetv-fixture";
in
pkgs.testers.runNixOSTest {
  name = "jellyfin-livetv";

  nodes.machine = { lib, ... }: {
    imports = [ nixosModules ];

    virtualisation = {
      diskSize = 3 * 1024;
      memorySize = 4096;
      cores = 4;
    };

    environment.systemPackages = [
      pkgs.jq
      pkgs.curl
    ];

    # Local M3U playlists and an XMLTV guide whose programmes are on now.
    # Jellyfin reads the M3U when a tuner is saved, so they exist first.
    systemd.services.livetv-fixture = {
      wantedBy = [ "multi-user.target" ];
      before = [ "jellyfin-livetv.service" ];
      requiredBy = [ "jellyfin-livetv.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.coreutils ];
      script = ''
        mkdir -p ${fixtures}
        cd ${fixtures}
        printf '%s\n' '#EXTM3U' \
          '#EXTINF:-1 tvg-id="news.test" tvg-chno="101",Test News' 'http://127.0.0.1:9/news.m3u8' \
          '#EXTINF:-1 tvg-id="kids.test" tvg-chno="102",Test Kids' 'http://127.0.0.1:9/kids.m3u8' >a.m3u
        printf '%s\n' '#EXTM3U' \
          '#EXTINF:-1 tvg-id="movies.test" tvg-chno="201",Test Movies' 'http://127.0.0.1:9/movies.m3u8' >b.m3u
        printf '%s\n' '#EXTM3U' \
          '#EXTINF:-1 tvg-id="manual.test" tvg-chno="301",Manual' 'http://127.0.0.1:9/manual.m3u8' >manual.m3u
        start=$(date -u -d '-1 hour' +%Y%m%d%H0000)
        stop=$(date -u -d '+5 hours' +%Y%m%d%H0000)
        cat >guide.xml <<EOF
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="news.test"><display-name>Test News</display-name></channel>
          <channel id="kids.test"><display-name>Test Kids</display-name></channel>
          <programme channel="news.test" start="$start +0000" stop="$stop +0000"><title>Morning News</title></programme>
          <programme channel="kids.test" start="$start +0000" stop="$stop +0000"><title>Cartoon Hour</title></programme>
        </tv>
        EOF
        cp guide.xml manual.xml
        chmod 0755 ${fixtures}
        chmod 0644 ${fixtures}/*
      '';
    };

    nixflix = {
      enable = true;
      jellyfin = {
        enable = true;
        apiKey._secret = pkgs.writeText "jellyfin-apikey" apiKey;
        users.admin = {
          password = "password123";
          policy.isAdministrator = true;
        };

        liveTv = {
          tuners = {
            a = {
              url = "${fixtures}/a.m3u";
              friendlyName = "Tuner A";
              settings = {
                tunerCount = 2;
                allowStreamSharing = true;
                ignoreDts = true;
              };
            };
            # The URL as a secret: only its path reaches the Nix store.
            b.url._secret = pkgs.writeText "tuner-b-url" "${fixtures}/b.m3u";
          };
          listingProviders.guide = {
            path = "${fixtures}/guide.xml";
            tuners = [ "a" ];
          };
        };
      };
    };

    specialisation = {
      # Tuner a renamed with a new setting, tuner b no longer declared.
      changed.configuration.nixflix.jellyfin.liveTv = {
        tuners = lib.mkForce {
          a = {
            url = "${fixtures}/a.m3u";
            friendlyName = "Renamed A";
            settings = {
              tunerCount = 3;
              allowStreamSharing = true;
              ignoreDts = true;
            };
          };
        };
      };
      # Nothing declared any more.
      empty.configuration.nixflix.jellyfin.liveTv = {
        tuners = lib.mkForce { };
        listingProviders = lib.mkForce { };
      };
    };
  };

  testScript = ''
    import json

    AUTH = 'Authorization: MediaBrowser Token="${apiKey}"'
    BASE = "http://127.0.0.1:8096"

    def api(path, method="GET", body=None):
        data = f" -H 'Content-Type: application/json' --data-binary '{json.dumps(body)}'" if body is not None else ""
        out = machine.succeed(f"curl -sf -X {method} -H '{AUTH}'{data} '{BASE}/{path}'")
        return json.loads(out) if out.strip() else None

    def livetv():
        return api("System/Configuration/livetv")

    def tuner(cfg, url):
        found = [t for t in cfg["TunerHosts"] if t["Url"] == url]
        assert len(found) <= 1, f"duplicate tuners for {url}: {found}"
        return found[0] if found else None

    def provider(cfg, path):
        found = [p for p in cfg["ListingProviders"] if p.get("Path") == path]
        assert len(found) <= 1, f"duplicate providers for {path}: {found}"
        return found[0] if found else None

    def switch(spec):
        machine.succeed(f"/run/booted-system/specialisation/{spec}/bin/switch-to-configuration test")
        machine.wait_for_unit("jellyfin-livetv.service", timeout=300)

    F = "${fixtures}"
    STATE = "/var/lib/jellyfin/nixflix-managed-livetv.json"

    start_all()
    machine.wait_for_unit("jellyfin.service", timeout=300)
    machine.wait_for_unit("jellyfin-livetv.service", timeout=600)
    print(machine.succeed("journalctl -u jellyfin-livetv --no-pager -o cat"))

    with subtest("declared tuners and guide are created"):
        cfg = livetv()
        a, b, g = tuner(cfg, f"{F}/a.m3u"), tuner(cfg, f"{F}/b.m3u"), provider(cfg, f"{F}/guide.xml")
        assert a and b and g, f"missing tuner or guide: {cfg}"
        assert a["Type"] == "m3u" and a["FriendlyName"] == "Tuner A", a
        assert b["FriendlyName"] == "b", b
        assert a["TunerCount"] == 2 and a["AllowStreamSharing"] is True and a["IgnoreDts"] is True, a
        assert g["Type"] == "xmltv" and g["EnableAllTuners"] is False and g["EnabledTuners"] == [a["Id"]], g
        a_id, g_id = a["Id"], g["Id"]

    with subtest("the secret tuner URL stays out of the store and the state file"):
        specs = machine.succeed("ls /nix/store/*-jellyfin-livetv.json").split()
        assert specs, "no jellyfin-livetv.json in the store"
        machine.fail(f"grep -l '{F}/b.m3u' {' '.join(specs)}")
        assert f"{F}/b.m3u" not in machine.succeed(f"cat {STATE}"), "secret URL written to the state file"

    with subtest("channels and programmes appear"):
        machine.wait_until_succeeds(
            f"curl -sf -H '{AUTH}' '{BASE}/LiveTv/Channels' | jq -e '.TotalRecordCount == 3'", timeout=180
        )
        machine.wait_until_succeeds(
            f"curl -sf -H '{AUTH}' '{BASE}/LiveTv/Programs' | jq -e '[.Items[].Name] | index(\"Morning News\")'",
            timeout=180,
        )

    with subtest("a second run against a converged Jellyfin writes nothing"):
        before = machine.succeed("stat -c %Y /var/lib/jellyfin/config/livetv.xml")
        machine.succeed("sleep 1; systemctl restart jellyfin-livetv.service")
        journal = machine.succeed("journalctl -u jellyfin-livetv --no-pager -o cat -n 20")
        assert "Live TV configuration unchanged" in journal, journal
        assert machine.succeed("stat -c %Y /var/lib/jellyfin/config/livetv.xml") == before, "livetv.xml rewritten"

    with subtest("a tuner and a guide added by hand"):
        manual = api("LiveTv/TunerHosts", "POST", {"Type": "m3u", "Url": f"{F}/manual.m3u", "FriendlyName": "Manual"})
        mp = api("LiveTv/ListingProviders?validateListings=false&validateLogin=false", "POST",
                 {"Type": "xmltv", "Path": f"{F}/manual.xml", "EnableAllTuners": True})
        manual_id, mp_id = manual["Id"], mp["Id"]

    with subtest("a changed declaration updates in place, an undeclared tuner is removed"):
        switch("changed")
        print(machine.succeed("journalctl -u jellyfin-livetv --no-pager -o cat -n 20"))
        cfg = livetv()
        a, g = tuner(cfg, f"{F}/a.m3u"), provider(cfg, f"{F}/guide.xml")
        assert a["Id"] == a_id, f"tuner a was replaced, not updated: {a_id} -> {a['Id']}"
        assert a["FriendlyName"] == "Renamed A" and a["TunerCount"] == 3, a
        assert tuner(cfg, f"{F}/b.m3u") is None, "tuner b should be removed"
        assert g["Id"] == g_id and g["EnabledTuners"] == [a_id], g
        assert tuner(cfg, f"{F}/manual.m3u")["Id"] == manual_id, "hand-added tuner was touched"
        assert provider(cfg, f"{F}/manual.xml")["Id"] == mp_id, "hand-added guide was touched"

    with subtest("declaring nothing removes what was managed and nothing else"):
        switch("empty")
        print(machine.succeed("journalctl -u jellyfin-livetv --no-pager -o cat -n 20"))
        cfg = livetv()
        assert tuner(cfg, f"{F}/a.m3u") is None and provider(cfg, f"{F}/guide.xml") is None, cfg
        assert tuner(cfg, f"{F}/manual.m3u")["Id"] == manual_id, "hand-added tuner was removed"
        assert provider(cfg, f"{F}/manual.xml")["Id"] == mp_id, "hand-added guide was removed"
        machine.fail(f"test -e {STATE}")
  '';
}
