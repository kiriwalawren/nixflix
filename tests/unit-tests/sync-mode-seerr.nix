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

  seerrConfig =
    {
      global ? null,
      seerrSyncMode ? { },
      enableAllLibraries ? false,
    }:
    evalConfig [
      {
        nixflix = {
          enable = true;
          seerr = {
            enable = true;
            apiKey._secret = "/run/secrets/seerr-api";
            jellyfin = {
              adminUsername = "admin";
              adminPassword = "password";
              inherit enableAllLibraries;
              libraryFilter.types = [ "movie" ];
            };
            radarr = {
              Main.apiKey._secret = "/run/secrets/radarr";
              "Radarr 4K" = {
                apiKey._secret = "/run/secrets/radarr4k";
                port = 7879;
                is4k = true;
              };
            };
            sonarr.Main.apiKey._secret = "/run/secrets/sonarr";
            syncMode = seerrSyncMode;
          };
        }
        // lib.optionalAttrs (global != null) { syncMode = global; };
      }
    ];

  # Everything a test needs from one evaluation: the unit scripts plus the
  # text of the library-sync script the seerr-libraries unit sources.
  render =
    args:
    let
      evaluated = seerrConfig args;
      inherit (evaluated) config;
      cfg = config.nixflix.seerr;
      evalPkgs = evaluated.pkgs;
      svcs = config.systemd.services;
      librarySync = import ../../modules/seerr/librarySync.nix {
        inherit lib cfg;
        pkgs = evalPkgs;
      } { inherit (cfg) apiKey; };
    in
    {
      inherit cfg evalPkgs;
      radarr = svcs.seerr-radarr.script;
      sonarr = svcs.seerr-sonarr.script;
      librariesUnit = svcs.seerr-libraries.script;
      inherit librarySync;
      libraries = librarySync.text;
    };

  # lib.hasInfix is a regex match, which rejects strings carrying store-path context.
  sources =
    r:
    lib.hasInfix (builtins.unsafeDiscardStringContext "source ${r.librarySync}") (
      builtins.unsafeDiscardStringContext r.librariesUnit
    );

  defaults = render { };
  globalKeep = render { global = "keep"; };
  globalRefuse = render { global = "refuse"; };

  # Text before the first match of `sep` (the whole text when it never matches).
  before = sep: text: builtins.head (lib.splitString sep text);
  count = sub: text: lib.length (lib.splitString sub text) - 1;

  radarrDeleteLoop = "'.[] | select([.name] | inside($configured[0]) | not) | .id')";
  libraryDeleteLoop = ''"\($id) \($enabled | index($id) != null)"'';

  # In refuse mode the guard and the single checkpoint precede every mutation.
  refuseShape =
    script:
    guardPrecedesMutations script
    && lib.hasInfix syncMode.refuseCheckpoint script
    && !lib.hasInfix "-X DELETE" (before syncMode.refuseCheckpoint script);

  # The library list can only be read through `POST .../library/sync` (it
  # refreshes Seerr's copy of the Jellyfin list and keeps each library's
  # enabled flag), so that one POST is allowed before the guard. Every PUT,
  # the only call that changes which libraries are enabled, comes after it.
  libraryRefuseShape =
    script:
    let
      preGuard = before "# nixflix-sync-guard" script;
    in
    lib.hasInfix "# nixflix-sync-guard" script
    && count "-X POST" preGuard == 1
    && lib.hasInfix "/api/v1/settings/jellyfin/library/sync" preGuard
    && !lib.hasInfix "-X PUT" preGuard
    && lib.hasInfix syncMode.refuseCheckpoint script
    && !lib.hasInfix "-X PUT" (before syncMode.refuseCheckpoint script);

  # A curl stand-in for running the real unit scripts in the sandbox. Logs
  # "METHOD PATH BODY" per call and answers from the fixture files.
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET out="" wfmt="" data="" url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift 2 ;;
        -o) out=$2; shift 2 ;;
        -w) wfmt=$2; shift 2 ;;
        -d) data=$2; shift 2 ;;
        -H | --header | --max-time | --variable | --expand-header) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    # mkSecureCurl sends bodies as `-d @-` on stdin.
    if [ "$data" = "@-" ]; then data=$(cat); fi
    path=''${url#"$BASE_URL"}
    printf '%s %s %s\n' "$method" "$path" "$(printf '%s' "$data" | ${pkgs.jq}/bin/jq -cS . 2>/dev/null)" >> "$CURL_LOG"
    case "$method $path" in
      "GET /api/v1/settings/radarr" | "GET /api/v1/settings/sonarr") body=$(cat "$FIXTURE_SERVERS") ;;
      "POST /api/v1/settings/"*/test) body='{"profiles":[{"id":1,"name":"HD"}]}' ;;
      "POST /api/v1/settings/jellyfin/library/sync") body=$(cat "$FIXTURE_LIBRARIES") ;;
      *) body='{}' ;;
    esac
    [ -n "$out" ] || printf '%s' "$body"
    case "$wfmt" in
      "") ;;
      '\n%{http_code}') printf '\n200' ;;
      *) printf '200' ;;
    esac
  '';

  # Stand-ins for the systemd credentials the *arr API keys are loaded from.
  credentials = pkgs.runCommand "sync-mode-seerr-credentials" { } ''
    mkdir $out
    for f in radarr-Main radarr-Radarr_4K sonarr-Main; do echo key > $out/$f-apikey; done
  '';

  # Runs a rendered script against fixtures with curl and auth stubbed out,
  # then runs `checks` against $rc, out.txt, err.txt and curl.log.
  runSeerr =
    name:
    {
      r,
      script,
      servers ? "[]",
      libraries ? "[]",
      checks,
    }:
    let
      stubbed =
        lib.replaceStrings
          [
            "${r.evalPkgs.curl}/bin/curl"
            "/run/credentials/seerr-radarr.service"
            "/run/credentials/seerr-sonarr.service"
          ]
          [ "${fakeCurl}" "${credentials}" "${credentials}" ]
          script;
      scriptFile = pkgs.writeText "${name}.sh" ''
        set -euo pipefail
        export BASE_URL="http://seerr.test"
        ${stubbed}
      '';
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export CURL_LOG=$PWD/curl.log
      export FIXTURE_SERVERS=${pkgs.writeText "servers.json" servers}
      export FIXTURE_LIBRARIES=${pkgs.writeText "libraries.json" libraries}
      touch curl.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt; echo "--- curl"; cat curl.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      mutations() { grep -E '^(POST|PUT|DELETE) ' curl.log | grep -v '^POST /api/v1/settings/jellyfin/library/sync ' || true; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  # Substrings of the declared "Radarr 4K".
  substringRadarr = builtins.toJSON [
    {
      id = 1;
      name = "Radarr";
    }
    {
      id = 2;
      name = "4K";
    }
    {
      id = 3;
      name = "Radarr 4K";
    }
  ];

  # Live Radarr servers: one declared (Main), one undeclared (Old).
  liveRadarr = builtins.toJSON [
    {
      id = 1;
      name = "Main";
      apiKey = "LIVESECRET";
    }
    {
      id = 7;
      name = "Old";
      apiKey = "LIVESECRET";
    }
  ];

  # Libraries for a `types = [ "movie" ]` filter: Movies matches, Shows is
  # enabled and would be disabled, Kids is already disabled.
  liveLibraries =
    showsEnabled:
    builtins.toJSON [
      {
        id = "m1";
        name = "Movies";
        type = "movie";
        enabled = false;
      }
      {
        id = "s1";
        name = "Shows";
        type = "show";
        enabled = showsEnabled;
      }
      {
        id = "k1";
        name = "Kids";
        type = "show";
        enabled = false;
      }
    ];
in
{
  sync-mode-seerr-options-default-to-global = assertTest "sync-mode-seerr-options-default-to-global" (
    defaults.cfg.syncMode == {
      radarr = "delete";
      sonarr = "delete";
      jellyfinLibraries = "delete";
      notifications = "delete";
    }
    &&
      globalKeep.cfg.syncMode == {
        radarr = "keep";
        sonarr = "keep";
        jellyfinLibraries = "keep";
        notifications = "keep";
      }
    &&
      globalRefuse.cfg.syncMode == {
        radarr = "refuse";
        sonarr = "refuse";
        jellyfinLibraries = "refuse";
        notifications = "refuse";
      }
  );

  # `syncMode` sits beside the server attrsets, so it is never a server.
  sync-mode-seerr-not-a-server = assertTest "sync-mode-seerr-not-a-server" (
    lib.attrNames globalRefuse.cfg.radarr == [
      "Main"
      "Radarr 4K"
    ]
    && lib.attrNames globalRefuse.cfg.sonarr == [ "Main" ]
  );

  sync-mode-seerr-delete-unchanged = assertTest "sync-mode-seerr-delete-unchanged" (
    lib.all (s: lib.hasInfix radarrDeleteLoop s && lib.hasInfix "-X DELETE" s) [
      defaults.radarr
      defaults.sonarr
    ]
    && lib.hasInfix libraryDeleteLoop defaults.libraries
    && lib.all (s: !lib.hasInfix "nixflix-sync-guard" s && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" s) [
      defaults.radarr
      defaults.sonarr
      defaults.libraries
    ]
    # The rendered script still sources the library script tested here.
    && sources defaults
  );

  sync-mode-seerr-refuse-shape = assertTest "sync-mode-seerr-refuse-shape" (
    refuseShape globalRefuse.radarr
    && refuseShape globalRefuse.sonarr
    && libraryRefuseShape globalRefuse.libraries
    && sources globalRefuse
  );

  sync-mode-seerr-keep-never-deletes = assertTest "sync-mode-seerr-keep-never-deletes" (
    !lib.hasInfix "-X DELETE" globalKeep.radarr
    && !lib.hasInfix "-X DELETE" globalKeep.sonarr
    && !lib.hasInfix libraryDeleteLoop globalKeep.libraries
    && !lib.hasInfix "LIB_ENABLED" globalKeep.libraries
    && lib.hasInfix "'{\"enabled\":true}'" globalKeep.libraries
    && !lib.hasInfix "nixflix-sync-guard" globalKeep.radarr
  );

  sync-mode-seerr-override-beats-global =
    let
      r = render {
        global = "refuse";
        seerrSyncMode = {
          radarr = "delete";
          jellyfinLibraries = "keep";
        };
      };
      d = render { seerrSyncMode.sonarr = "refuse"; };
    in
    assertTest "sync-mode-seerr-override-beats-global" (
      r.radarr == defaults.radarr
      && refuseShape r.sonarr
      && r.libraries == globalKeep.libraries
      && d.radarr == defaults.radarr
      && d.libraries == defaults.libraries
      && d.sonarr == globalRefuse.sonarr
    );

  # With every library enabled there is nothing to disable, so the mode is moot.
  sync-mode-seerr-enable-all-libraries-unaffected =
    let
      text =
        mode:
        (render {
          enableAllLibraries = true;
          global = mode;
        }).libraries;
    in
    assertTest "sync-mode-seerr-enable-all-libraries-unaffected" (
      text "keep" == text "delete" && text "refuse" == text "delete"
    );

  sync-mode-seerr-radarr-delete-run = runSeerr "sync-mode-seerr-radarr-delete-run" {
    r = defaults;
    script = defaults.radarr;
    servers = liveRadarr;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      grep -qx 'DELETE /api/v1/settings/radarr/7 ' curl.log || fail "Old not deleted"
      [ "$(grep -c '^DELETE ' curl.log)" = 1 ] || fail "deleted more than Old"
    '';
  };

  sync-mode-seerr-radarr-keep-run = runSeerr "sync-mode-seerr-radarr-keep-run" {
    r = globalKeep;
    script = globalKeep.radarr;
    servers = liveRadarr;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q '^DELETE ' curl.log || fail "keep deleted a server"
      grep -q '^PUT /api/v1/settings/radarr/1 ' curl.log || fail "Main not updated"
      grep -q '^POST /api/v1/settings/radarr {' curl.log || fail "Radarr 4K not created"
      expectLine out.txt 'nixflix: seerr-radarr: keeping 1 undeclared Radarr servers (nixflix.seerr.syncMode.radarr = "keep"): Old'
      ! grep -q LIVESECRET out.txt err.txt || fail "server contents leaked"
    '';
  };

  sync-mode-seerr-radarr-refuse-run = runSeerr "sync-mode-seerr-radarr-refuse-run" {
    r = globalRefuse;
    script = globalRefuse.radarr;
    servers = liveRadarr;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ -z "$(mutations)" ] || fail "refuse mutated: $(mutations)"
      [ "$(cat curl.log)" = 'GET /api/v1/settings/radarr ' ] || fail "unexpected calls"
      expectLine err.txt 'nixflix: seerr-radarr: refusing to sync: 1 Radarr servers exist that are not declared (nixflix.seerr.syncMode.radarr = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - Old (id 7)'
      ! grep -q 'nixflix:   - Main ' err.txt || fail "declared server listed"
      ! grep -q LIVESECRET out.txt err.txt || fail "server contents leaked"
    '';
  };

  sync-mode-seerr-radarr-refuse-all-declared-run =
    runSeerr "sync-mode-seerr-radarr-refuse-all-declared-run"
      {
        r = globalRefuse;
        script = globalRefuse.radarr;
        servers = builtins.toJSON [
          {
            id = 1;
            name = "Main";
          }
        ];
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          grep -q '^PUT /api/v1/settings/radarr/1 ' curl.log || fail "Main not updated"
          grep -q '^POST /api/v1/settings/radarr {' curl.log || fail "Radarr 4K not created"
          ! grep -q '^DELETE ' curl.log || fail "refuse deleted a server"
        '';
      };

  # The delete loop matches with jq `inside`, i.e. by substring: with "Radarr 4K"
  # declared, live "Radarr" and "4K" are not deleted, so refuse and keep must
  # not flag them either.
  sync-mode-seerr-radarr-substring-delete-run =
    runSeerr "sync-mode-seerr-radarr-substring-delete-run"
      {
        r = defaults;
        script = defaults.radarr;
        servers = substringRadarr;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          ! grep -q '^DELETE ' curl.log || fail "delete deleted: $(grep '^DELETE ' curl.log)"
        '';
      };

  sync-mode-seerr-radarr-substring-refuse-run =
    runSeerr "sync-mode-seerr-radarr-substring-refuse-run"
      {
        r = globalRefuse;
        script = globalRefuse.radarr;
        servers = substringRadarr;
        checks = ''
          [ "$rc" = 0 ] || fail "expected rc 0 (delete deletes nothing), got $rc"
          ! grep -q refusing err.txt || fail "refused"
          ! grep -q '^DELETE ' curl.log || fail "refuse deleted a server"
          grep -q '^PUT /api/v1/settings/radarr/3 ' curl.log || fail "Radarr 4K not updated"
        '';
      };

  sync-mode-seerr-radarr-substring-keep-run = runSeerr "sync-mode-seerr-radarr-substring-keep-run" {
    r = globalKeep;
    script = globalKeep.radarr;
    servers = substringRadarr;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q keeping out.txt || fail "keep listed servers delete would not delete"
      ! grep -q '^DELETE ' curl.log || fail "keep deleted a server"
    '';
  };

  # A name that is not a substring of any declared one is still flagged.
  sync-mode-seerr-radarr-substring-refuse-other-run =
    runSeerr "sync-mode-seerr-radarr-substring-refuse-other-run"
      {
        r = globalRefuse;
        script = globalRefuse.radarr;
        servers = builtins.toJSON [
          {
            id = 3;
            name = "Radarr 4K";
          }
          {
            id = 4;
            name = "Radarr 4K HDR";
          }
        ];
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          expectLine err.txt 'nixflix:   - Radarr 4K HDR (id 4)'
          [ -z "$(mutations)" ] || fail "refuse mutated: $(mutations)"
        '';
      };

  # Same substring matching in seerr-sonarr: "Ma" is part of the declared "Main".
  sync-mode-seerr-sonarr-substring-refuse-run =
    runSeerr "sync-mode-seerr-sonarr-substring-refuse-run"
      {
        r = globalRefuse;
        script = globalRefuse.sonarr;
        servers = builtins.toJSON [
          {
            id = 1;
            name = "Main";
          }
          {
            id = 2;
            name = "Ma";
          }
        ];
        checks = ''
          [ "$rc" = 0 ] || fail "expected rc 0 (delete deletes nothing), got $rc"
          ! grep -q '^DELETE ' curl.log || fail "refuse deleted a server"
        '';
      };

  sync-mode-seerr-sonarr-refuse-run = runSeerr "sync-mode-seerr-sonarr-refuse-run" {
    r = globalRefuse;
    script = globalRefuse.sonarr;
    servers = liveRadarr;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ -z "$(mutations)" ] || fail "refuse mutated: $(mutations)"
      expectLine err.txt 'nixflix:   - Old (id 7)'
    '';
  };

  sync-mode-seerr-sonarr-keep-run = runSeerr "sync-mode-seerr-sonarr-keep-run" {
    r = globalKeep;
    script = globalKeep.sonarr;
    servers = liveRadarr;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q '^DELETE ' curl.log || fail "keep deleted a server"
      grep -q '^PUT /api/v1/settings/sonarr/1 ' curl.log || fail "Main not updated"
      expectLine out.txt 'nixflix: seerr-sonarr: keeping 1 undeclared Sonarr servers (nixflix.seerr.syncMode.sonarr = "keep"): Old'
    '';
  };

  sync-mode-seerr-libraries-delete-run = runSeerr "sync-mode-seerr-libraries-delete-run" {
    r = defaults;
    script = defaults.libraries;
    libraries = liveLibraries true;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      expectLine curl.log 'PUT /api/v1/settings/jellyfin/library/m1 {"enabled":true}'
      expectLine curl.log 'PUT /api/v1/settings/jellyfin/library/s1 {"enabled":false}'
      expectLine curl.log 'PUT /api/v1/settings/jellyfin/library/k1 {"enabled":false}'
    '';
  };

  sync-mode-seerr-libraries-keep-run = runSeerr "sync-mode-seerr-libraries-keep-run" {
    r = globalKeep;
    script = globalKeep.libraries;
    libraries = liveLibraries true;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      [ "$(mutations)" = 'PUT /api/v1/settings/jellyfin/library/m1 {"enabled":true}' ] || fail "unexpected mutations: $(mutations)"
      expectLine out.txt 'nixflix: seerr-libraries: keeping 1 undeclared enabled Jellyfin libraries (nixflix.seerr.syncMode.jellyfinLibraries = "keep"): Shows'
    '';
  };

  sync-mode-seerr-libraries-refuse-run = runSeerr "sync-mode-seerr-libraries-refuse-run" {
    r = globalRefuse;
    script = globalRefuse.libraries;
    libraries = liveLibraries true;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ -z "$(mutations)" ] || fail "refuse mutated: $(mutations)"
      expectLine err.txt 'nixflix:   - Shows (id s1)'
      ! grep -qE 'nixflix:   - (Movies|Kids) ' err.txt || fail "library that would not be disabled listed"
    '';
  };

  # Already-disabled libraries outside the filter do not block the sync.
  sync-mode-seerr-libraries-refuse-nothing-to-disable-run =
    runSeerr "sync-mode-seerr-libraries-refuse-nothing-to-disable-run"
      {
        r = globalRefuse;
        script = globalRefuse.libraries;
        libraries = liveLibraries false;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(mutations)" = 'PUT /api/v1/settings/jellyfin/library/m1 {"enabled":true}' ] || fail "unexpected mutations: $(mutations)"
        '';
      };
}
