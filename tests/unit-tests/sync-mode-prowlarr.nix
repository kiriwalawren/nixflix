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

  baseProwlarr = {
    nixflix = {
      enable = true;
      prowlarr = {
        enable = true;
        config = {
          apiKey._secret = "/run/secrets/prowlarr-api";
          hostConfig.password._secret = "/run/secrets/prowlarr-pass";
        };
      };
    };
  };

  # Declares one object per collection, so every unit has create/update calls
  # (POST/PUT) that the refuse guard has to precede.
  declared = {
    nixflix.prowlarr.config = {
      indexers = [
        { name = "Declared Indexer"; }
        {
          name = "New Indexer";
          schemaName = "Generic Newznab";
          baseUrl = "http://127.0.0.1:1";
        }
      ];
      indexerProxies = [
        {
          name = "Http";
          host = "127.0.0.1";
          port = 3128;
        }
      ];
      applications = [
        {
          name = "Declared App";
          implementationName = "Sonarr";
          apiKey = "appkey";
          baseUrl = "http://127.0.0.1:8989";
          prowlarrUrl = "http://127.0.0.1:9696";
        }
      ];
    };
  };

  eval = modules: (evalConfig ([ baseProwlarr ] ++ modules)).config;
  services = modules: (eval modules).systemd.services;
  scriptOf = modules: unit: (services modules).${unit}.script;

  # unit -> collection option name and the API path of its DELETE call.
  units = {
    prowlarr-indexers = {
      collection = "indexers";
      deletePath = "/indexer/$INDEXER_ID";
      removing = "Removing indexers not in configuration...";
    };
    prowlarr-indexer-proxies = {
      collection = "indexerProxies";
      deletePath = "/indexerProxy/$INDEXER_ID";
      removing = "Removing indexer proxies not in configuration...";
    };
    prowlarr-applications = {
      collection = "applications";
      deletePath = "/applications/$APPLICATION_ID";
      removing = "Removing applications not in configuration...";
    };
  };

  allUnits = lib.attrNames units;
  forAllUnits = f: lib.all (unit: f unit units.${unit}) allUnits;

  hasDelete = script: lib.hasInfix "-X DELETE" script;
  hasGuard = script: lib.hasInfix "# nixflix-sync-guard" script;
  hasCheckpoint = script: lib.hasInfix syncMode.refuseCheckpoint script;
  hasMutation = script: builtins.match ".*-X (POST|PUT).*" script != null;

  # The checkpoint sits before every mutating call, not merely after a guard.
  checkpointPrecedesMutations =
    script:
    let
      before = builtins.head (builtins.split "-X (POST|PUT|DELETE)" script);
    in
    lib.hasInfix syncMode.refuseCheckpoint before;

  # Stands in for curl: answers GETs from $FIXTURES/<path with / as _>.json
  # (default `[]`) and records every other request in $MUTATED_LOG.
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET out="" wfmt="" url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift 2 ;;
        -o) out=$2; shift 2 ;;
        -w) wfmt=$2; shift 2 ;;
        --variable|--expand-header|--header|-H|--data-binary|-d) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    path=''${url#*/api/v1/}
    path=''${path%%\?*}
    if [ "$method" = GET ]; then
      f="$FIXTURES/$(printf '%s' "$path" | tr / _).json"
      if [ -f "$f" ]; then body=$(cat "$f"); else body='[]'; fi
    else
      echo "$method $path" >> "$MUTATED_LOG"
      body='{}'
    fi
    if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    if [ -n "$wfmt" ]; then printf 200; fi
  '';

  liveFixtures = pkgs.linkFarm "sync-mode-prowlarr-fixtures" (
    lib.mapAttrsToList
      (name: value: {
        name = "${name}.json";
        path = pkgs.writeText "${name}.json" (builtins.toJSON value);
      })
      {
        indexer = [
          {
            id = 1;
            name = "Declared Indexer";
            fields = [ ];
            tags = [ ];
          }
          {
            id = 2;
            name = "Stray Indexer";
            fields = [
              {
                name = "apiKey";
                value = "SUPERSECRET";
              }
            ];
          }
        ];
        indexer_schema = [
          {
            name = "Generic Newznab";
            indexerUrls = [ ];
            fields = [
              {
                name = "baseUrl";
                value = "";
              }
            ];
          }
        ];
        indexerProxy = [
          {
            id = 5;
            name = "Http";
            fields = [ ];
          }
          {
            id = 6;
            name = "Stray Proxy";
            fields = [ ];
          }
        ];
        applications = [
          {
            id = 8;
            name = "Declared App";
            fields = [ ];
          }
          {
            id = 9;
            name = "Stray App";
            fields = [
              {
                name = "apiKey";
                value = "SUPERSECRET";
              }
            ];
          }
        ];
      }
  );

  # Runs the real unit script with curl replaced by fakeCurl, then `checks`
  # against $rc, out.txt, err.txt and mutated.log.
  runUnit =
    name:
    {
      modules,
      unit,
      checks,
    }:
    let
      script = builtins.replaceStrings [ "${pkgs.curl}/bin/curl" ] [ "${fakeCurl}" ] (
        scriptOf modules unit
      );
      scriptFile = pkgs.writeText "${name}.sh" script;
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export FIXTURES=${liveFixtures} MUTATED_LOG=$PWD/mutated.log
      touch mutated.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt
      echo "--- mutations"; cat mutated.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      noSecrets() { ! grep -q SUPERSECRET out.txt err.txt || fail "object contents leaked"; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';
in
{
  sync-mode-prowlarr-options-default-to-global =
    assertTest "sync-mode-prowlarr-options-default-to-global"
      (
        let
          modes = settings: (eval [ { nixflix = settings; } ]).nixflix.prowlarr.syncMode;
          all = mode: m: m.indexers == mode && m.indexerProxies == mode && m.applications == mode;
        in
        all "delete" (modes { })
        && all "keep" (modes {
          syncMode = "keep";
        })
        && all "refuse" (modes {
          syncMode = "refuse";
        })
      );

  # The default renders the same script as an explicit "delete", which still
  # holds the unit's original delete loop and nothing from the helper.
  sync-mode-prowlarr-default-keeps-delete-loop =
    assertTest "sync-mode-prowlarr-default-keeps-delete-loop"
      (
        forAllUnits (
          unit: u:
          let
            default = scriptOf [ declared ] unit;
            explicit = scriptOf [
              declared
              { nixflix.prowlarr.syncMode.${u.collection} = "delete"; }
            ] unit;
          in
          default == explicit
          && hasDelete default
          && lib.hasInfix u.deletePath default
          && lib.hasInfix u.removing default
          && !hasGuard default
          && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" default
        )
      );

  sync-mode-prowlarr-refuse-guards-before-mutations =
    assertTest "sync-mode-prowlarr-refuse-guards-before-mutations"
      (
        forAllUnits (
          unit: _:
          let
            script = scriptOf [
              declared
              { nixflix.syncMode = "refuse"; }
            ] unit;
          in
          guardPrecedesMutations script
          && hasCheckpoint script
          && checkpointPrecedesMutations script
          && hasMutation script
          && !hasDelete script
        )
      );

  # With nothing declared the units are still enabled; refuse must protect
  # every live object instead of deleting them all.
  sync-mode-prowlarr-refuse-empty-declared = assertTest "sync-mode-prowlarr-refuse-empty-declared" (
    forAllUnits (
      unit: _:
      let
        script = scriptOf [ { nixflix.syncMode = "refuse"; } ] unit;
      in
      guardPrecedesMutations script && hasCheckpoint script && !hasDelete script
    )
  );

  sync-mode-prowlarr-keep-never-deletes = assertTest "sync-mode-prowlarr-keep-never-deletes" (
    forAllUnits (
      unit: _:
      let
        script = scriptOf [
          declared
          { nixflix.syncMode = "keep"; }
        ] unit;
      in
      !hasDelete script
      && hasMutation script
      && lib.hasInfix "keeping " script
      && !hasCheckpoint script
      && !hasGuard script
    )
  );

  sync-mode-prowlarr-override-beats-global = assertTest "sync-mode-prowlarr-override-beats-global" (
    let
      mixed = [
        declared
        {
          nixflix.syncMode = "refuse";
          nixflix.prowlarr.syncMode.indexers = "delete";
          nixflix.prowlarr.syncMode.indexerProxies = "keep";
        }
      ];
      idx = scriptOf mixed "prowlarr-indexers";
      prx = scriptOf mixed "prowlarr-indexer-proxies";
      app = scriptOf mixed "prowlarr-applications";
    in
    idx == scriptOf [ declared ] "prowlarr-indexers"
    && !hasDelete prx
    && !hasCheckpoint prx
    && lib.hasInfix "keeping " prx
    && hasCheckpoint app
    && !hasDelete app
  );

  # Only the proxies unit restarts on failure; a refusal must not loop.
  sync-mode-prowlarr-restart-prevent-exit-status =
    assertTest "sync-mode-prowlarr-restart-prevent-exit-status"
      (
        let
          sc = modules: unit: (services modules).${unit}.serviceConfig;
          refuse = [ { nixflix.syncMode = "refuse"; } ];
        in
        (sc refuse "prowlarr-indexer-proxies").RestartPreventExitStatus == 78
        && (sc refuse "prowlarr-indexer-proxies").Restart == "on-failure"
        && !((sc [ ] "prowlarr-indexer-proxies") ? RestartPreventExitStatus)
        && !((sc [ { nixflix.syncMode = "keep"; } ] "prowlarr-indexer-proxies") ? RestartPreventExitStatus)
        && !((sc refuse "prowlarr-indexers") ? Restart)
        && !((sc refuse "prowlarr-applications") ? Restart)
      );

  sync-mode-prowlarr-syncmode-not-in-config = assertTest "sync-mode-prowlarr-syncmode-not-in-config" (
    !((eval [ ]).nixflix.prowlarr.config ? syncMode)
  );
}
// lib.listToAttrs (
  lib.concatMap (
    unit:
    let
      u = units.${unit};
      inherit (u) collection;
      strayLabel =
        {
          indexers = "Stray Indexer (id 2)";
          indexerProxies = "Stray Proxy (id 6)";
          applications = "Stray App (id 9)";
        }
        .${collection};
      strayDelete =
        {
          indexers = "DELETE indexer/2";
          indexerProxies = "DELETE indexerProxy/6";
          applications = "DELETE applications/9";
        }
        .${collection};
      what =
        {
          indexers = "indexers";
          indexerProxies = "indexer proxies";
          applications = "applications";
        }
        .${collection};
      testName = mode: "sync-mode-prowlarr-run-${unit}-${mode}";
      mk = mode: checks: {
        name = testName mode;
        value = runUnit (testName mode) {
          inherit unit checks;
          modules = [
            declared
            { nixflix.syncMode = mode; }
          ];
        };
      };
    in
    [
      (mk "delete" ''
        [ "$rc" = 0 ] || fail "rc=$rc"
        grep -qFx ${lib.escapeShellArg strayDelete} mutated.log || fail "undeclared object not deleted"
        [ "$(grep -c '^DELETE ' mutated.log)" = 1 ] || fail "deleted a declared object"
      '')
      (mk "keep" ''
        [ "$rc" = 0 ] || fail "rc=$rc"
        ! grep -q '^DELETE ' mutated.log || fail "keep deleted something"
        grep -qE '^(POST|PUT) ' mutated.log || fail "keep must still create/update"
        grep -qF ${lib.escapeShellArg "nixflix: ${unit}: keeping 1 undeclared ${what}"} out.txt || fail "no keep log"
        noSecrets
      '')
      (mk "refuse" ''
        [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
        [ ! -s mutated.log ] || fail "refuse let the unit mutate"
        expectLine err.txt ${lib.escapeShellArg "nixflix: ${unit}: refusing to sync: 1 ${what} exist that are not declared (nixflix.prowlarr.syncMode.${collection} = \"refuse\"). Nothing was changed."}
        expectLine err.txt ${lib.escapeShellArg "nixflix:   - ${strayLabel}"}
        noSecrets
      '')
    ]
  ) allUnits
)
