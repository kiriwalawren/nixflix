{
  pkgs,
  lib,
  evalConfig,
  assertTest,
  guardPrecedesMutations,
  ...
}:
let
  syncMode = import ../../lib/sync-mode.nix { inherit lib pkgs; };
  inherit (syncMode) refuseCheckpoint;

  # Replaced by the scenario's own directory at run time.
  dataDir = "/nixflix-test-data";

  fakePlugin = pkgs.runCommand "fake-plugin-1.0.0.0" { } ''
    mkdir -p "$out"
    echo dll > "$out/Fake.dll"
  '';

  # Embedded in a tuner URL and a guide path; must never reach the logs.
  secret = "SECRETPASS";
  oldTunerUrl = "http://user:${secret}@old.example/old.m3u";
  oldGuidePath = "http://${secret}@old.example/guide.xml";
  secretTunerUrl = pkgs.writeText "tuner-b-url" "http://b.example/${secret}-b.m3u";

  base = {
    nixflix = {
      enable = true;
      jellyfin = {
        enable = true;
        inherit dataDir;
        apiKey = "test-jellyfin-key";
        users.admin = {
          password = "testpassword";
          policy.isAdministrator = true;
        };
        libraries = {
          Movies = {
            collectionType = "movies";
            paths = [ "/srv/movies" ];
          };
          # Declared with a new collectionType: recreated, an update.
          Kids = {
            collectionType = "tvshows";
            paths = [ "/srv/kids" ];
          };
        };
        plugins."Fake Plugin" = {
          enable = true;
          package = fakePlugin;
        };
        liveTv = {
          tuners = {
            a = {
              url = "/srv/a.m3u";
              friendlyName = "Tuner A";
            };
            b.url._secret = secretTunerUrl;
          };
          listingProviders.guide = {
            path = "/srv/guide.xml";
            tuners = [ "a" ];
          };
        };
      };
    };
  };

  eval =
    settings:
    (evalConfig [
      base
      { nixflix = settings; }
    ]).config;
  scriptsOf =
    settings:
    let
      c = eval settings;
      s = c.systemd.services;
    in
    {
      libraries = s.jellyfin-libraries.script;
      plugins = s.jellyfin-plugins.script;
      livetv = s.jellyfin-livetv.script;
      waitForApi = toString s.jellyfin-livetv.serviceConfig.ExecStartPre;
      modes = c.nixflix.jellyfin.syncMode;
    };

  default = scriptsOf { };
  keep = scriptsOf { syncMode = "keep"; };
  refuse = scriptsOf { syncMode = "refuse"; };

  units = [
    "libraries"
    "plugins"
    "livetv"
  ];

  # The code the unit runs before its refuse checkpoint.
  beforeCheckpoint = script: builtins.head (lib.splitString refuseCheckpoint script);
  countOf = needle: text: builtins.length (lib.splitString needle text) - 1;

  # Fragments of each unit's own delete loop (delete mode only).
  deleteLoops = {
    libraries = [
      "Deleting removed library: $lib_name"
      "Removing path: $existing_path"
    ];
    plugins = [ "Removed managed plugin directory: $old_dir" ];
    livetv = [
      ''api DELETE "LiveTv/TunerHosts?id=$id"''
      ''api DELETE "LiveTv/ListingProviders?id=$id"''
    ];
  };
  hasNone = needles: script: lib.all (n: !lib.hasInfix n script) needles;
  hasAll = needles: script: lib.all (n: lib.hasInfix n script) needles;

  mutatingCalls = [
    "-X POST"
    "-X PUT"
    "-X DELETE"
    "api POST"
    "api DELETE"
    "rm -rf"
    "systemctl stop"
    "mkdir -p"
    "> \"$STATE_FILE\""
  ];

  # Runs a rendered unit script with curl, systemctl, auth and the API wait
  # stubbed, the data dir moved into the build directory, and the scenario's
  # fixtures. Steps run in order, each followed by its checks; a step's logs
  # land in <name>.{out,err,rc,mutated}. Every non-GET request, systemctl
  # start/stop and library mkdir goes to mutated.log.
  stubs = pkgs.writeText "sync-mode-jellyfin-stubs.sh" ''
    curl_stub() {
      local method=GET url="" w=0
      while [ $# -gt 0 ]; do
        case "$1" in
          -X) method=$2; shift 2 ;;
          -w) w=1; shift 2 ;;
          --variable|--expand-header|--header|-H|--data-binary|-d|-m) shift 2 ;;
          *) url=$1; shift ;;
        esac
      done
      [ "$method" = GET ] || echo "$method $url" >> "$MUTATED_LOG"
      case "$method $url" in
        "GET "*/Library/VirtualFolders) cat "$FIXTURES/libraries.json" ;;
        "GET "*/System/Configuration/livetv) cat "$FIXTURES/livetv.json" ;;
        "POST "*/LiveTv/TunerHosts) echo '{"Id":"new-tuner"}' ;;
        "POST "*/LiveTv/ListingProviders*) echo '{"Id":"new-guide"}' ;;
        "GET "*/ScheduledTasks) echo '[{"Key":"RefreshGuide","Id":"task-1"}]' ;;
      esac
      if [ "$w" = 1 ]; then printf '\n200'; fi
      return 0
    }
    curl() { curl_stub "$@"; }
    systemctl() {
      case "$1" in
        is-active) return 0 ;;
        *) echo "systemctl $*" >> "$MUTATED_LOG" ;;
      esac
    }
    mkdir() { echo "mkdir $*" >> "$MUTATED_LOG"; }
    source() { :; }
  '';

  prepare =
    s: script:
    pkgs.writeText "sync-mode-jellyfin-unit.sh" (
      ''
        source ${stubs}
      ''
      +
        builtins.replaceStrings
          [ "${pkgs.curl}/bin/curl" "${pkgs.coreutils}/bin/chown" s.waitForApi ]
          [ "curl_stub" "true" ":" ]
          script
    );

  runScenario =
    name:
    {
      setup,
      steps,
      checks ? "",
    }:
    pkgs.runCommand "unit-test-${name}"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.gnused
        ];
      }
      ''
        export DATA=$PWD/data FIXTURES=$PWD/fixtures MUTATED_LOG=$PWD/mutated.log
        ${pkgs.coreutils}/bin/mkdir -p "$DATA" "$FIXTURES"
        touch mutated.log
        ${setup}

        fail() { echo "FAIL: ${name}: $*"; exit 1; }
        expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
        run() { # NAME SCRIPT
          sed "s|${dataDir}|$DATA|g" "$2" > "$1.sh"
          : > mutated.log
          rc=0
          bash "$1.sh" > "$1.out" 2> "$1.err" || rc=$?
          echo "$rc" > "$1.rc"
          cp mutated.log "$1.mutated"
          echo "=== $1: rc=$rc"; echo "--- stdout"; cat "$1.out"; echo "--- stderr"; cat "$1.err"; echo "--- mutated"; cat "$1.mutated"
        }
        ${lib.concatMapStringsSep "\n" (step: ''
          run ${step.name} ${step.script}
          ${step.checks}
        '') steps}

        ${checks}
        echo 'PASS: ${name}' > $out
      '';

  libraryFixture = builtins.toJSON [
    {
      Name = "Movies";
      CollectionType = "movies";
      ItemId = "i-movies";
      Locations = [
        "/srv/movies"
        "/srv/extra"
      ];
    }
    {
      Name = "Old";
      CollectionType = "movies";
      ItemId = "i-old";
      Locations = [ "/srv/old" ];
    }
    {
      Name = "Manual";
      CollectionType = "tvshows";
      ItemId = "i-manual";
      Locations = [ "/srv/manual" ];
    }
    {
      Name = "Kids";
      CollectionType = "movies";
      ItemId = "i-kids";
      Locations = [ "/srv/kids-old" ];
    }
  ];

  librarySetup = ''
    cp ${pkgs.writeText "libraries.json" libraryFixture} "$FIXTURES/libraries.json"
    echo '["Movies","Old","Kids"]' > "$DATA/nixflix-managed-libraries.json"
  '';

  sha = s: builtins.hashString "sha256" s;
  livetvFixture = builtins.toJSON {
    TunerHosts = [
      {
        Id = "t-a";
        Type = "m3u";
        Url = "/srv/a.m3u";
        FriendlyName = "Tuner A";
      }
      {
        Id = "t-old";
        Type = "m3u";
        Url = oldTunerUrl;
        FriendlyName = "Old Tuner";
      }
      {
        Id = "t-manual";
        Type = "m3u";
        Url = "/srv/manual.m3u";
        FriendlyName = "Manual";
      }
    ];
    ListingProviders = [
      {
        Id = "g-guide";
        Type = "xmltv";
        Path = "/srv/guide.xml";
        EnableAllTuners = false;
        EnabledTuners = [ "t-a" ];
      }
      {
        Id = "g-old";
        Type = "xmltv";
        Path = oldGuidePath;
      }
      {
        Id = "g-sd";
        Type = "SchedulesDirect";
      }
    ];
  };
  livetvState = builtins.toJSON {
    tuners = [
      (sha "/srv/a.m3u")
      (sha oldTunerUrl)
    ];
    providers = [
      (sha "/srv/guide.xml")
      (sha oldGuidePath)
    ];
  };
  livetvSetup = ''
    cp ${pkgs.writeText "livetv.json" livetvFixture} "$FIXTURES/livetv.json"
    cp ${pkgs.writeText "livetv-state.json" livetvState} "$DATA/nixflix-managed-livetv.json"
    chmod u+w "$DATA/nixflix-managed-livetv.json"
  '';

  pluginSetup = ''
    ${pkgs.coreutils}/bin/mkdir -p "$DATA/plugins/Old_1.0.0.0" "$DATA/plugins/fake-plugin_0.9.0.0" "$DATA/plugins/manual"
    echo '{"Old Plugin":{"dir":"Old_1.0.0.0","path":null},"Fake Plugin":{"dir":"fake-plugin_0.9.0.0","path":null}}' \
      > "$DATA/nixflix-managed-plugins.json"
  '';

  step = s: unit: name: checks: {
    inherit name checks;
    script = prepare s s.${unit};
  };
in
{
  sync-mode-jellyfin-option-defaults = assertTest "sync-mode-jellyfin-option-defaults" (
    default.modes == {
      libraries = "delete";
      libraryPaths = "delete";
      plugins = "delete";
      liveTv = "delete";
    }
    && lib.all (m: m == "keep") (lib.attrValues keep.modes)
    && lib.all (m: m == "refuse") (lib.attrValues refuse.modes)
  );

  sync-mode-jellyfin-default-keeps-delete-loops =
    assertTest "sync-mode-jellyfin-default-keeps-delete-loops"
      (
        lib.all (
          u:
          hasAll deleteLoops.${u} default.${u}
          && !lib.hasInfix "nixflix-sync-guard" default.${u}
          && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" default.${u}
          && !lib.hasInfix "NIXFLIX_" default.${u}
        ) units
      );

  sync-mode-jellyfin-refuse-guards-first = assertTest "sync-mode-jellyfin-refuse-guards-first" (
    lib.all (
      u:
      let
        script = refuse.${u};
        early = beforeCheckpoint script;
      in
      guardPrecedesMutations script
      && lib.hasInfix refuseCheckpoint script
      && lib.hasInfix "# nixflix-sync-guard" early
      && lib.all (m: !lib.hasInfix m early) mutatingCalls
      && hasNone deleteLoops.${u} script
    ) units
  );

  # The only DELETE left under keep/refuse is the collectionType recreate of
  # a declared library (one per library); live TV issues none.
  sync-mode-jellyfin-keep-has-no-deletes = assertTest "sync-mode-jellyfin-keep-has-no-deletes" (
    lib.all (u: hasNone deleteLoops.${u} keep.${u}) units
    && countOf "-X DELETE" keep.libraries == 2
    && countOf "-X DELETE" refuse.libraries == 2
    && countOf "-X DELETE" default.libraries == 5
    && lib.hasInfix "recreating library" keep.libraries
    && !lib.hasInfix "api DELETE" keep.livetv
    && !lib.hasInfix "Removed managed plugin directory" keep.plugins
    && !lib.hasInfix "nixflix-sync-guard" keep.libraries
  );

  sync-mode-jellyfin-override-beats-global =
    let
      mixed = scriptsOf {
        syncMode = "refuse";
        jellyfin.syncMode.libraryPaths = "delete";
        jellyfin.syncMode.plugins = "delete";
      };
      keepPaths = scriptsOf { jellyfin.syncMode.libraryPaths = "keep"; };
    in
    assertTest "sync-mode-jellyfin-override-beats-global" (
      mixed.modes == {
        libraries = "refuse";
        libraryPaths = "delete";
        plugins = "delete";
        liveTv = "refuse";
      }
      # paths are still pruned, after the libraries guard and checkpoint
      && lib.hasInfix "Removing path: $existing_path" mixed.libraries
      && !lib.hasInfix "Removing path:" (beforeCheckpoint mixed.libraries)
      && !lib.hasInfix "Deleting removed library" mixed.libraries
      && guardPrecedesMutations mixed.libraries
      && mixed.plugins == default.plugins
      && lib.hasInfix "nixflix-sync-guard" mixed.livetv
      # a per-collection keep under the default global
      && lib.hasInfix "Deleting removed library: $lib_name" keepPaths.libraries
      && !lib.hasInfix "Removing path:" keepPaths.libraries
      && keepPaths.plugins == default.plugins
      && keepPaths.livetv == default.livetv
    );

  sync-mode-jellyfin-libraries-runtime = runScenario "sync-mode-jellyfin-libraries-runtime" {
    setup = ''
      ${librarySetup}
      state() { jq -c 'sort' "$DATA/nixflix-managed-libraries.json"; }
    '';
    steps = [
      (step refuse "libraries" "refuse" ''
        # refuse: lists the managed library and the undeclared path, changes nothing
        [ "$(cat refuse.rc)" = 78 ] || fail "refuse rc=$(cat refuse.rc)"
        [ ! -s refuse.mutated ] || fail "refuse mutated: $(cat refuse.mutated)"
        expectLine refuse.err 'nixflix: jellyfin-libraries: refusing to sync: 1 nixflix-managed libraries exist that are not declared (nixflix.jellyfin.syncMode.libraries = "refuse"). Nothing was changed.'
        expectLine refuse.err 'nixflix:   - Old (id i-old)'
        expectLine refuse.err 'nixflix: jellyfin-libraries: refusing to sync: 1 library paths exist that are not declared (nixflix.jellyfin.syncMode.libraryPaths = "refuse"). Nothing was changed.'
        expectLine refuse.err 'nixflix:   - Movies: /srv/extra (id i-movies)'
        ! grep -qE 'Manual|kids-old' refuse.err || fail "refuse listed an unmanaged library or a recreated library's path"
        [ "$(state)" = '["Kids","Movies","Old"]' ] || fail "refuse changed the state: $(state)"
      '')
      (step keep "libraries" "keep" ''
        # keep: creates/updates, deletes only for the Kids recreate, keeps Old in the state
        [ "$(cat keep.rc)" = 0 ] || fail "keep rc=$(cat keep.rc)"
        [ "$(grep -c '^DELETE' keep.mutated)" = 1 ] || fail "keep deleted: $(grep '^DELETE' keep.mutated)"
        grep -qF 'DELETE http://127.0.0.1:8096/Library/VirtualFolders?name=Kids' keep.mutated || fail "Kids not recreated"
        grep -qF 'POST http://127.0.0.1:8096/Library/VirtualFolders/LibraryOptions' keep.mutated || fail "keep did not update"
        expectLine keep.out 'nixflix: jellyfin-libraries: keeping 1 undeclared nixflix-managed libraries (nixflix.jellyfin.syncMode.libraries = "keep"): Old'
        expectLine keep.out 'nixflix: jellyfin-libraries: keeping 1 undeclared library paths (nixflix.jellyfin.syncMode.libraryPaths = "keep"): Movies: /srv/extra'
        [ "$(state)" = '["Kids","Movies","Old"]' ] || fail "keep dropped a kept library from the state: $(state)"
      '')
      (step default "libraries" "delete" ''
        # delete after keep: the kept library is still known, so it is removed now
        [ "$(cat delete.rc)" = 0 ] || fail "delete rc=$(cat delete.rc)"
        grep -qF 'DELETE http://127.0.0.1:8096/Library/VirtualFolders?name=Old' delete.mutated || fail "Old not deleted"
        grep -qF 'DELETE http://127.0.0.1:8096/Library/VirtualFolders/Paths?name=Movies&path=%2Fsrv%2Fextra' delete.mutated || fail "path not removed"
        ! grep -qF 'name=Manual' delete.mutated || fail "deleted an unmanaged library"
        [ "$(state)" = '["Kids","Movies"]' ] || fail "delete state: $(state)"
      '')
    ];
  };

  sync-mode-jellyfin-plugins-runtime = runScenario "sync-mode-jellyfin-plugins-runtime" {
    setup = ''
      ${pluginSetup}
      P=$DATA/plugins
    '';
    steps = [
      (step refuse "plugins" "refuse" ''
        [ "$(cat refuse.rc)" = 78 ] || fail "refuse rc=$(cat refuse.rc)"
        [ ! -s refuse.mutated ] || fail "refuse mutated (Jellyfin stopped?): $(cat refuse.mutated)"
        expectLine refuse.err 'nixflix: jellyfin-plugins: refusing to sync: 1 nixflix-managed plugin directories exist that are not declared (nixflix.jellyfin.syncMode.plugins = "refuse"). Nothing was changed.'
        expectLine refuse.err 'nixflix:   - Old_1.0.0.0 (id Old_1.0.0.0)'
        ! grep -qE 'fake-plugin_0.9.0.0|manual' refuse.err || fail "refuse listed a superseded or unmanaged directory"
        [ -d "$P/Old_1.0.0.0" ] && [ -d "$P/fake-plugin_0.9.0.0" ] || fail "refuse removed a directory"
      '')
      (step keep "plugins" "keep" ''
        # keep: the superseded version of a declared plugin is replaced, Old stays
        [ "$(cat keep.rc)" = 0 ] || fail "keep rc=$(cat keep.rc)"
        [ -d "$P/Old_1.0.0.0" ] || fail "keep removed Old"
        [ ! -e "$P/fake-plugin_0.9.0.0" ] || fail "keep left the superseded version"
        [ -f "$P/fake-plugin_1.0.0.0/Fake.dll" ] || fail "keep did not install the declared plugin"
        [ -d "$P/manual" ] || fail "unmanaged directory touched"
        expectLine keep.out 'nixflix: jellyfin-plugins: keeping 1 undeclared nixflix-managed plugin directories (nixflix.jellyfin.syncMode.plugins = "keep"): Old_1.0.0.0'
        jq -e '."Old Plugin".dir == "Old_1.0.0.0" and ."Fake Plugin".dir == "fake-plugin_1.0.0.0"' "$DATA/nixflix-managed-plugins.json" >/dev/null \
          || fail "keep state: $(cat "$DATA/nixflix-managed-plugins.json")"
      '')
      (step keep "plugins" "keep2" ''
        # a second keep run sees no change: Jellyfin is not restarted every boot
        [ "$(cat keep2.rc)" = 0 ] || fail "keep2 rc=$(cat keep2.rc)"
        grep -qFx 'No plugin file changes detected' keep2.out || fail "keep restarts Jellyfin on every run"
        [ ! -s keep2.mutated ] || fail "keep2 mutated: $(cat keep2.mutated)"
      '')
      (step default "plugins" "delete" ''
        # delete after keep removes the kept directory
        [ "$(cat delete.rc)" = 0 ] || fail "delete rc=$(cat delete.rc)"
        [ ! -e "$P/Old_1.0.0.0" ] || fail "delete left the kept directory"
        [ -d "$P/manual" ] && [ -f "$P/fake-plugin_1.0.0.0/Fake.dll" ] || fail "delete removed too much"
      '')
    ];
  };

  sync-mode-jellyfin-livetv-runtime = runScenario "sync-mode-jellyfin-livetv-runtime" {
    setup = ''
      ${livetvSetup}
      ST=$DATA/nixflix-managed-livetv.json
      hasHash() { jq -e --arg h "$2" ".$1 | index(\$h)" "$ST" >/dev/null; }
    '';
    steps = [
      (step refuse "livetv" "refuse" ''
        [ "$(cat refuse.rc)" = 78 ] || fail "refuse rc=$(cat refuse.rc)"
        [ ! -s refuse.mutated ] || fail "refuse mutated: $(cat refuse.mutated)"
        expectLine refuse.err 'nixflix: jellyfin-livetv: refusing to sync: 1 nixflix-managed Live TV tuners exist that are not declared (nixflix.jellyfin.syncMode.liveTv = "refuse"). Nothing was changed.'
        expectLine refuse.err 'nixflix:   - Old Tuner (id t-old)'
        expectLine refuse.err 'nixflix: jellyfin-livetv: refusing to sync: 1 nixflix-managed Live TV guides exist that are not declared (nixflix.jellyfin.syncMode.liveTv = "refuse"). Nothing was changed.'
        expectLine refuse.err 'nixflix:   - xmltv (id g-old)'
        ! grep -qE 't-manual|g-sd' refuse.err || fail "refuse listed an unmanaged tuner/guide"
        cmp -s "$ST" ${pkgs.writeText "livetv-state.json" livetvState} || fail "refuse changed the state"
      '')
      (step keep "livetv" "keep" ''
        [ "$(cat keep.rc)" = 0 ] || fail "keep rc=$(cat keep.rc)"
        ! grep -q '^DELETE' keep.mutated || fail "keep deleted: $(grep '^DELETE' keep.mutated)"
        grep -qF 'POST http://127.0.0.1:8096/LiveTv/TunerHosts' keep.mutated || fail "keep did not create tuner b"
        expectLine keep.out 'nixflix: jellyfin-livetv: keeping 1 undeclared nixflix-managed Live TV tuners (nixflix.jellyfin.syncMode.liveTv = "keep"): Old Tuner'
        expectLine keep.out 'nixflix: jellyfin-livetv: keeping 1 undeclared nixflix-managed Live TV guides (nixflix.jellyfin.syncMode.liveTv = "keep"): xmltv'
        hasHash tuners ${sha oldTunerUrl} && hasHash providers ${sha oldGuidePath} \
          || fail "keep dropped kept tuners/guides from the state: $(cat "$ST")"
        hasHash tuners ${sha "/srv/a.m3u"} && hasHash tuners ${sha "http://b.example/${secret}-b.m3u"} \
          || fail "keep state lost a declared tuner: $(cat "$ST")"
      '')
      (step default "livetv" "delete" ''
        [ "$(cat delete.rc)" = 0 ] || fail "delete rc=$(cat delete.rc)"
        grep -qFx 'DELETE http://127.0.0.1:8096/LiveTv/TunerHosts?id=t-old' delete.mutated || fail "old tuner not deleted"
        grep -qFx 'DELETE http://127.0.0.1:8096/LiveTv/ListingProviders?id=g-old' delete.mutated || fail "old guide not deleted"
        ! grep -qE 'id=(t-manual|g-sd)' delete.mutated || fail "deleted an unmanaged tuner/guide"
        ! hasHash tuners ${sha oldTunerUrl} || fail "delete kept the old tuner in the state"
      '')
    ];
    checks = ''
      # Tuner URLs and guide paths can carry credentials: never logged.
      ! grep -l ${secret} ./*.out ./*.err || fail "a secret URL reached the logs"
    '';
  };
}
