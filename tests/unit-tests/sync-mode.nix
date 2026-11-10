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

  # Stand-in for a unit's existing delete loop: records what it would delete.
  onDelete = ''
    printf '%s' "$LIVE" | ${pkgs.jq}/bin/jq -r '.[].id' | while IFS= read -r id; do
      echo "$id" >> "$DELETED_LOG"
    done
  '';

  prune =
    args:
    syncMode.mkPrune (
      {
        unit = "test-unit";
        what = "things";
        option = "nixflix.test.syncMode.things";
        live = "LIVE";
        inherit onDelete;
      }
      // args
    );

  # Runs `script` with each `fixtures` value (raw text) loaded into the shell
  # variable of the same name, then runs `checks` against its exit code ($rc),
  # stdout (out.txt), stderr (err.txt) and side effects (deleted.log,
  # mutated.log).
  runScenario =
    name:
    {
      fixtures,
      script,
      checks,
    }:
    let
      loadFixtures = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: text: "${var}=$(cat ${pkgs.writeText "fixture-${var}" text})") fixtures
      );
      scriptFile = pkgs.writeText "sync-mode-${name}.sh" ''
        set -eu
        ${loadFixtures}
        ${script}
      '';
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export DELETED_LOG=$PWD/deleted.log MUTATED_LOG=$PWD/mutated.log
      touch deleted.log mutated.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  # A single-collection unit wired the way adopting units must wire it.
  singleUnit = p: ''
    ${p.guard}
    ${syncMode.refuseCheckpoint}
    echo mutated >> "$MUTATED_LOG"
    ${p.prune}
  '';

  things = builtins.toJSON [
    {
      id = 1;
      name = "a";
    }
    {
      id = 2;
      name = "b";
      apiKey = "SUPERSECRET";
    }
    {
      id = 3;
      name = "c";
    }
  ];

  refuseThings = prune {
    mode = "refuse";
    declared = [ "a" ];
  };
in
{
  sync-mode-global-default =
    let
      config = evalConfig [ { nixflix.enable = true; } ];
    in
    assertTest "sync-mode-global-default" (config.config.nixflix.syncMode == "delete");

  sync-mode-option-inherits-global =
    let
      withOverride =
        settings:
        (evalConfig [
          ({ config, ... }: {
            options.nixflix.test.syncMode.things = syncMode.mkModeOption {
              inherit config;
              what = "things";
              collectionOption = "nixflix.test.config.things";
            };
            config.nixflix = settings;
          })
        ]).config.nixflix.test.syncMode.things;
    in
    assertTest "sync-mode-option-inherits-global" (
      withOverride { } == "delete"
      && withOverride { syncMode = "keep"; } == "keep"
      && withOverride { syncMode = "refuse"; } == "refuse"
      && withOverride { test.syncMode.things = "refuse"; } == "refuse"
      &&
        withOverride {
          syncMode = "refuse";
          test.syncMode.things = "delete";
        } == "delete"
    );

  sync-mode-delete-is-ondelete-verbatim =
    let
      p = prune {
        mode = "delete";
        declared = [ "a" ];
      };
    in
    assertTest "sync-mode-delete-is-ondelete-verbatim" (p.guard == "" && p.prune == onDelete);

  sync-mode-refuse-checkpoint-text = assertTest "sync-mode-refuse-checkpoint-text" (
    syncMode.refuseCheckpoint == ''if [ "''${NIXFLIX_SYNC_REFUSED:-0}" = 1 ]; then exit 78; fi''
    && syncMode.refuseExitCode == 78
    &&
      syncMode.modes == [
        "delete"
        "keep"
        "refuse"
      ]
  );

  sync-mode-guard-precedes-mutations-helper = assertTest "sync-mode-guard-precedes-mutations-helper" (
    guardPrecedesMutations "${refuseThings.guard}\ncurl -X DELETE x"
    && !guardPrecedesMutations "curl -X POST x\n${refuseThings.guard}"
    && !guardPrecedesMutations "systemctl stop foo\n${refuseThings.guard}"
    && !guardPrecedesMutations "rm -rf /x\n${refuseThings.guard}"
    && !guardPrecedesMutations "del_config x\n${refuseThings.guard}"
    && !guardPrecedesMutations "echo no guard here"
    && guardPrecedesMutations (singleUnit refuseThings)
    # every mutation shape counts, ahead of the guard
    && lib.all (m: !guardPrecedesMutations "${m}\n${refuseThings.guard}") [
      "curl -X PATCH x"
      "curl -X PUT x"
      "api POST x"
      "api PUT x"
      "api DELETE x"
      "api PATCH x"
      "set_config x"
      "systemctl start foo"
      "systemctl restart foo"
      "rm -f /x"
      "mkdir -p /x"
      "mv a b"
      "cp a b"
      "chown a b"
      "chmod 640 b"
      "echo x > \"$STATE_FILE\""
      "echo x >>\"$LOG\""
      "echo x > '/var/lib/x'"
      "echo x > /var/lib/x"
    ]
    # reads, /dev redirects and plain words are not mutations
    && guardPrecedesMutations "curl -s x >/dev/null 2>&1\napi GET x\necho ok >&2\necho cpu mvp\n${refuseThings.guard}\ncurl -X POST x"
    # function definitions are skipped, their calls are not
    && guardPrecedesMutations "f() {\n  systemctl start x\n}\n${refuseThings.guard}\nf"
    && !guardPrecedesMutations "f() {\n  systemctl start x\n}\nf\n${refuseThings.guard}"
    && !guardPrecedesMutations "f() {\n  systemctl start x\n}\ng() {\n  f\n}\ng\n${refuseThings.guard}"
    && !guardPrecedesMutations "s() { rm -f x; }\ns\n${refuseThings.guard}"
    && guardPrecedesMutations "s() { rm -f x; }\nsx=1\n${refuseThings.guard}\ns"
    # `<fn> GET` is the read form of a method-taking helper
    && guardPrecedesMutations "api() {\n  curl -X \"$1\" > \"$bf\"\n}\nr=$(api GET x)\n${refuseThings.guard}\napi POST y"
    && !guardPrecedesMutations "api() {\n  curl -X \"$1\" > \"$bf\"\n}\nr=$(api FOO x)\n${refuseThings.guard}"
  );

  sync-mode-delete-runs-ondelete = runScenario "sync-mode-delete-runs-ondelete" {
    fixtures.LIVE = things;
    script = singleUnit (prune {
      mode = "delete";
      declared = [ "a" ];
    });
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      [ "$(cat deleted.log | tr '\n' ' ')" = "1 2 3 " ] || fail "onDelete did not run"
    '';
  };

  sync-mode-keep-logs-and-deletes-nothing = runScenario "sync-mode-keep-logs-and-deletes-nothing" {
    fixtures.LIVE = things;
    script = singleUnit (prune {
      mode = "keep";
      declared = [ "a" ];
    });
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      [ ! -s deleted.log ] || fail "keep deleted something"
      grep -q mutated mutated.log || fail "keep must still create/update"
      expectLine out.txt 'nixflix: test-unit: keeping 2 undeclared things (nixflix.test.syncMode.things = "keep"): b, c'
      ! grep -q SUPERSECRET out.txt err.txt || fail "object contents leaked"
    '';
  };

  sync-mode-keep-silent-when-all-declared = runScenario "sync-mode-keep-silent-when-all-declared" {
    fixtures.LIVE = things;
    script = singleUnit (prune {
      mode = "keep";
      declared = [
        "a"
        "b"
        "c"
      ];
    });
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q keeping out.txt || fail "logged keeping with nothing undeclared"
    '';
  };

  sync-mode-refuse-undeclared = runScenario "sync-mode-refuse-undeclared" {
    fixtures.LIVE = things;
    script = singleUnit refuseThings;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s deleted.log ] || fail "refuse deleted something"
      [ ! -s mutated.log ] || fail "refuse let the unit mutate"
      expectLine err.txt 'nixflix: test-unit: refusing to sync: 2 things exist that are not declared (nixflix.test.syncMode.things = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - b (id 2)'
      expectLine err.txt 'nixflix:   - c (id 3)'
      expectLine err.txt 'nixflix: declare them (see nixflix.test.syncMode.things), or set it to "keep" or "delete".'
      ! grep -q 'nixflix:   - a ' err.txt || fail "declared object listed"
      ! grep -q SUPERSECRET out.txt err.txt || fail "object contents leaked"
    '';
  };

  sync-mode-refuse-all-declared = runScenario "sync-mode-refuse-all-declared" {
    fixtures.LIVE = things;
    script = singleUnit (prune {
      mode = "refuse";
      declared = [
        "a"
        "b"
        "c"
      ];
    });
    checks = ''
      [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
      grep -q mutated mutated.log || fail "sync did not proceed"
      [ ! -s deleted.log ] || fail "refuse deleted something"
      [ ! -s err.txt ] || fail "unexpected stderr"
    '';
  };

  sync-mode-refuse-empty-array-proceeds = runScenario "sync-mode-refuse-empty-array-proceeds" {
    fixtures.LIVE = "[]";
    script = singleUnit refuseThings;
    checks = ''
      [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
    '';
  };

  sync-mode-refuse-bad-live-state = runScenario "sync-mode-refuse-bad-live-state" {
    fixtures = {
      EMPTY = "";
      OBJ = ''{"message":"Unauthorized"}'';
      NULLV = "null";
      HTML = "<html>502 Bad Gateway</html>";
    };
    script =
      lib.concatMapStringsSep "\n"
        (var: ''
          rc=0
          (
            ${(prune {
              mode = "refuse";
              live = var;
              declared = [ "a" ];
            }).guard
            }
            ${syncMode.refuseCheckpoint}
            echo mutated >> "$MUTATED_LOG"
          ) || rc=$?
          echo "${var} $rc"
        '')
        [
          "EMPTY"
          "OBJ"
          "NULLV"
          "HTML"
        ];
    checks = ''
      [ "$rc" = 0 ] || fail "driver failed rc=$rc"
      for v in EMPTY OBJ NULLV HTML; do
        expectLine out.txt "$v 1"
      done
      [ ! -s mutated.log ] || fail "mutated after a failed GET"
      grep -q 'nixflix: test-unit: cannot check for undeclared things' err.txt || fail "no error message"
    '';
  };

  sync-mode-ignore-and-select = runScenario "sync-mode-ignore-and-select" {
    fixtures.LIVE = builtins.toJSON [
      {
        id = 1;
        name = "a";
      }
      {
        id = 2;
        name = "Any";
        preset = true;
      }
      {
        id = 3;
        name = "builtin";
      }
      {
        id = 4;
        name = "x";
      }
    ];
    script = singleUnit (prune {
      mode = "refuse";
      declared = [ "a" ];
      ignore = [ "builtin" ];
      select = "(.preset // false) | not";
    });
    checks = ''
      [ "$rc" = 78 ] || fail "rc=$rc"
      expectLine err.txt 'nixflix: test-unit: refusing to sync: 1 things exist that are not declared (nixflix.test.syncMode.things = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - x (id 4)'
      ! grep -qE 'nixflix:   - (Any|builtin|a) ' err.txt || fail "selected-out or ignored object listed"
    '';
  };

  sync-mode-awkward-labels = runScenario "sync-mode-awkward-labels" {
    fixtures.LIVE = builtins.toJSON [
      {
        id = 1;
        name = "has spaces  and\ttab";
      }
      {
        id = 2;
        name = ''quo"te's $(touch pwned) `x` *'';
      }
      {
        id = 3;
        name = "Ünïcødé 名前 🎬";
      }
      {
        id = 4;
        name = "multi\nline";
      }
    ];
    script = ''
      ${singleUnit refuseThings}
    '';
    checks = ''
      [ "$rc" = 78 ] || fail "rc=$rc"
      expectLine err.txt "$(printf 'nixflix:   - has spaces  and\ttab (id 1)')"
      expectLine err.txt 'nixflix:   - quo"te'"'"'s $(touch pwned) `x` * (id 2)'
      expectLine err.txt 'nixflix:   - Ünïcødé 名前 🎬 (id 3)'
      expectLine err.txt 'nixflix:   - multi line (id 4)'
      [ ! -e pwned ] || fail "label was executed"
    '';
  };

  sync-mode-awkward-labels-keep = runScenario "sync-mode-awkward-labels-keep" {
    fixtures.LIVE = builtins.toJSON [
      {
        id = 1;
        name = "a";
      }
      {
        id = 2;
        name = ''q"uo'te $(touch pwned)'';
      }
      {
        id = 3;
        name = "Ünïcødé";
      }
    ];
    script = singleUnit (prune {
      mode = "keep";
      declared = [ "a" ];
    });
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      expectLine out.txt 'nixflix: test-unit: keeping 2 undeclared things (nixflix.test.syncMode.things = "keep"): q"uo'"'"'te $(touch pwned), Ünïcødé'
      [ ! -e pwned ] || fail "label was executed"
    '';
  };

  sync-mode-int-keys = runScenario "sync-mode-int-keys" {
    fixtures.LIVE = things;
    script = singleUnit (prune {
      mode = "refuse";
      key = ".id";
      label = ".name";
      declared = [
        1
        3
      ];
      ignore = [ 99 ];
    });
    checks = ''
      [ "$rc" = 78 ] || fail "rc=$rc"
      expectLine err.txt 'nixflix: test-unit: refusing to sync: 1 things exist that are not declared (nixflix.test.syncMode.things = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - b (id 2)'
    '';
  };

  # Only an exact key match counts as declared ("a" is a prefix of "ab").
  sync-mode-exact-match = runScenario "sync-mode-exact-match" {
    fixtures.LIVE = builtins.toJSON [
      {
        id = 1;
        name = "a";
      }
    ];
    script = singleUnit (prune {
      mode = "refuse";
      declared = [ "ab" ];
    });
    checks = ''
      [ "$rc" = 78 ] || fail "rc=$rc"
      expectLine err.txt 'nixflix:   - a (id 1)'
    '';
  };

  sync-mode-multiple-collections-one-checkpoint =
    runScenario "sync-mode-multiple-collections-one-checkpoint"
      {
        fixtures = {
          LIVE = things;
          OTHER = builtins.toJSON [
            {
              id = 7;
              name = "z";
            }
          ];
        };
        script =
          let
            first = refuseThings;
            second = prune {
              mode = "refuse";
              live = "OTHER";
              what = "widgets";
              option = "nixflix.test.syncMode.widgets";
              declared = [ ];
            };
          in
          ''
            ${first.guard}
            ${second.guard}
            ${syncMode.refuseCheckpoint}
            echo mutated >> "$MUTATED_LOG"
          '';
        checks = ''
          [ "$rc" = 78 ] || fail "rc=$rc"
          [ ! -s mutated.log ] || fail "mutated"
          expectLine err.txt 'nixflix:   - b (id 2)'
          expectLine err.txt 'nixflix:   - z (id 7)'
          expectLine err.txt 'nixflix: test-unit: refusing to sync: 1 widgets exist that are not declared (nixflix.test.syncMode.widgets = "refuse"). Nothing was changed.'
        '';
      };
}
