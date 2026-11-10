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

  baseConfig = {
    nixflix = {
      enable = true;
      sonarr = {
        enable = true;
        config = {
          apiKey._secret = "/run/secrets/sonarr-api";
          hostConfig.password._secret = "/run/secrets/sonarr-pass";
        };
      };
      radarr = {
        enable = true;
        config = {
          apiKey._secret = "/run/secrets/radarr-api";
          hostConfig.password._secret = "/run/secrets/radarr-pass";
        };
      };
      recyclarr = {
        enable = true;
        cleanupUnmanagedProfiles = {
          enable = true;
          managedProfiles = [ "Managed" ];
        };
        config.sonarr.sonarr.base_url = "http://sonarr.test";
        config.radarr.radarr.base_url = "http://radarr.test";
      };
    };
  };

  eval =
    extra:
    (evalConfig [
      baseConfig
      { nixflix = extra; }
    ]).config;

  # The cleanup unit runs an ExecStart script, not `script`.
  cleanupScript = cfg: cfg.systemd.services.recyclarr-cleanup-profiles.serviceConfig.ExecStart.text;

  scriptFor = extra: cleanupScript (eval extra);

  defaultScript = scriptFor { };
  refuseScript = scriptFor { recyclarr.syncMode.qualityProfiles = "refuse"; };
  keepScript = scriptFor { recyclarr.syncMode.qualityProfiles = "keep"; };

  hasDelete = lib.hasInfix "-X DELETE";
  hasPut = lib.hasInfix "-X PUT";

  # Everything before the refuse checkpoint, i.e. what runs even when refusing.
  beforeCheckpoint = s: builtins.head (lib.splitString syncMode.refuseCheckpoint s);

  oldCustomFormats =
    cfg:
    map (i: i.delete_old_custom_formats) [
      cfg.nixflix.recyclarr.config.sonarr.sonarr
      cfg.nixflix.recyclarr.config.radarr.radarr
    ];

  recyclarrWarnings =
    cfg: builtins.filter (lib.hasPrefix "nixflix.recyclarr.syncMode.customFormats") cfg.warnings;

  # Fake curl: logs "METHOD URL" for every call and answers GETs from
  # $FIXTURES/<host>-<last path segment>; DELETE answers HTTP 204.
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET
    url=
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift ;;
        http://*) url=$1 ;;
      esac
      shift
    done
    echo "$method $url" >> "$CALL_LOG"
    case "$method" in
      GET)
        host=''${url#http://}; host=''${host%%/*}
        cat "$FIXTURES/$host-''${url##*/}"
        ;;
      DELETE) printf '\n204\n' ;;
      *) echo '{}' ;;
    esac
  '';

  fixtures =
    files:
    pkgs.linkFarm "sync-mode-recyclarr-fixtures" (
      lib.mapAttrsToList (name: value: {
        inherit name;
        path = pkgs.writeText name (builtins.toJSON value);
      }) files
    );

  runCleanup =
    name:
    {
      script,
      files,
      checks,
    }:
    let
      scriptFile = pkgs.writeText "${name}.sh" (
        builtins.replaceStrings [ "${pkgs.curl}/bin/curl" ] [ "${fakeCurl}" ] script
      );
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export CALL_LOG=$PWD/calls.log FIXTURES=${fixtures files}
      touch calls.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- calls"; cat calls.log
      echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      mutations() { grep -vE '^GET ' calls.log || true; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  # sonarr is clean; radarr (processed second) has an undeclared profile in use.
  liveState = {
    "sonarr.test-qualityprofile" = [
      {
        id = 1;
        name = "Managed";
      }
    ];
    "sonarr.test-series" = [ ];
    "radarr.test-qualityprofile" = [
      {
        id = 1;
        name = "Managed";
      }
      {
        id = 5;
        name = "Old Profile";
        secretish = "SHOULD-NOT-PRINT";
      }
    ];
    "radarr.test-movie" = [
      {
        id = 10;
        title = "A Movie";
        qualityProfileId = 5;
      }
    ];
  };
in
{
  sync-mode-recyclarr-qp-default-is-delete = assertTest "sync-mode-recyclarr-qp-default-is-delete" (
    (eval { }).nixflix.recyclarr.syncMode.qualityProfiles == "delete"
    && hasDelete defaultScript
    && hasPut defaultScript
    && lib.hasInfix "Found $PROFILE_COUNT unmanaged profile(s) to delete" defaultScript
    && !lib.hasInfix "# nixflix-sync-guard" defaultScript
    && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" defaultScript
  );

  sync-mode-recyclarr-qp-refuse-guards-first =
    assertTest "sync-mode-recyclarr-qp-refuse-guards-first"
      (
        guardPrecedesMutations refuseScript
        && lib.hasInfix syncMode.refuseCheckpoint refuseScript
        && !hasDelete refuseScript
        && !hasPut refuseScript
        && !hasDelete (beforeCheckpoint refuseScript)
        # one guard per instance, all before the single checkpoint
        && builtins.length (lib.splitString "# nixflix-sync-guard" (beforeCheckpoint refuseScript)) == 3
        && builtins.length (lib.splitString syncMode.refuseCheckpoint refuseScript) == 2
      );

  sync-mode-recyclarr-qp-keep-no-delete = assertTest "sync-mode-recyclarr-qp-keep-no-delete" (
    !hasDelete keepScript
    && !hasPut keepScript
    && lib.hasInfix "keeping" keepScript
    && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" keepScript
  );

  sync-mode-recyclarr-qp-override-and-global =
    assertTest "sync-mode-recyclarr-qp-override-and-global"
      (
        let
          mode = extra: (eval extra).nixflix.recyclarr.syncMode.qualityProfiles;
        in
        mode { syncMode = "keep"; } == "keep"
        && mode { syncMode = "refuse"; } == "refuse"
        &&
          mode {
            syncMode = "refuse";
            recyclarr.syncMode.qualityProfiles = "delete";
          } == "delete"
        && scriptFor { syncMode = "keep"; } == keepScript
        && scriptFor { syncMode = "refuse"; } == refuseScript
        &&
          scriptFor {
            syncMode = "refuse";
            recyclarr.syncMode.qualityProfiles = "delete";
          } == defaultScript
      );

  sync-mode-recyclarr-cf-default-delete = assertTest "sync-mode-recyclarr-cf-default-delete" (
    let
      cfg = eval { };
    in
    cfg.nixflix.recyclarr.syncMode.customFormats == "delete"
    &&
      oldCustomFormats cfg == [
        true
        true
      ]
    && cfg.services.recyclarr.configuration.sonarr.sonarr.delete_old_custom_formats
    && recyclarrWarnings cfg == [ ]
  );

  sync-mode-recyclarr-cf-keep-and-refuse = assertTest "sync-mode-recyclarr-cf-keep-and-refuse" (
    let
      keep = eval { recyclarr.syncMode.customFormats = "keep"; };
      refuse = eval { syncMode = "refuse"; };
      overridden = eval {
        syncMode = "refuse";
        recyclarr.syncMode.customFormats = "delete";
      };
      explicit = eval {
        recyclarr.syncMode.customFormats = "keep";
        recyclarr.config.radarr.radarr.delete_old_custom_formats = true;
      };
      disabled =
        (evalConfig [
          {
            nixflix = {
              enable = true;
              syncMode = "refuse";
            };
          }
        ]).config;
    in
    oldCustomFormats keep == [
      false
      false
    ]
    && recyclarrWarnings keep == [ ]
    && refuse.nixflix.recyclarr.syncMode.customFormats == "refuse"
    &&
      oldCustomFormats refuse == [
        false
        false
      ]
    && builtins.length (recyclarrWarnings refuse) == 1
    &&
      oldCustomFormats overridden == [
        true
        true
      ]
    && recyclarrWarnings overridden == [ ]
    &&
      oldCustomFormats explicit == [
        false
        true
      ]
    && recyclarrWarnings disabled == [ ]
  );

  sync-mode-recyclarr-syncmode-not-in-recyclarr-config =
    assertTest "sync-mode-recyclarr-syncmode-not-in-recyclarr-config"
      (
        let
          configuration = (eval { syncMode = "refuse"; }).services.recyclarr.configuration;
        in
        !(configuration ? syncMode)
        && !(configuration.sonarr.sonarr ? syncMode)
        && !(configuration.radarr.radarr ? syncMode)
      );

  sync-mode-recyclarr-run-refuse = runCleanup "sync-mode-recyclarr-run-refuse" {
    script = refuseScript;
    files = liveState;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ -z "$(mutations)" ] || fail "refuse mutated: $(mutations)"
      expectLine calls.log 'GET http://sonarr.test/api/v3/qualityprofile'
      expectLine calls.log 'GET http://radarr.test/api/v3/qualityprofile'
      expectLine err.txt 'nixflix:   - Old Profile (id 5)'
      grep -qF 'refusing to sync: 1 quality profiles in radarr instance radarr exist' err.txt \
        || fail "refuse message missing"
      ! grep -q 'Managed (id' err.txt || fail "managed profile listed"
      ! grep -q SHOULD-NOT-PRINT out.txt err.txt || fail "profile contents leaked"
    '';
  };

  sync-mode-recyclarr-run-refuse-clean = runCleanup "sync-mode-recyclarr-run-refuse-clean" {
    script = refuseScript;
    files = liveState // {
      "radarr.test-qualityprofile" = [
        {
          id = 1;
          name = "Managed";
        }
      ];
    };
    checks = ''
      [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
      [ -z "$(mutations)" ] || fail "mutated: $(mutations)"
      grep -q 'Quality profile cleanup completed' out.txt || fail "did not complete"
    '';
  };

  sync-mode-recyclarr-run-keep = runCleanup "sync-mode-recyclarr-run-keep" {
    script = keepScript;
    files = liveState;
    checks = ''
      [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
      [ -z "$(mutations)" ] || fail "keep mutated: $(mutations)"
      expectLine out.txt 'nixflix: recyclarr-cleanup-profiles: keeping 1 undeclared quality profiles in radarr instance radarr (nixflix.recyclarr.syncMode.qualityProfiles = "keep"): Old Profile'
      ! grep -q SHOULD-NOT-PRINT out.txt err.txt || fail "profile contents leaked"
    '';
  };

  sync-mode-recyclarr-run-delete = runCleanup "sync-mode-recyclarr-run-delete" {
    script = defaultScript;
    files = liveState;
    checks = ''
      [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
      expectLine calls.log 'PUT http://radarr.test/api/v3/movie/10'
      expectLine calls.log 'DELETE http://radarr.test/api/v3/qualityprofile/5'
      [ "$(mutations | wc -l)" = 2 ] || fail "unexpected mutations: $(mutations)"
    '';
  };
}
