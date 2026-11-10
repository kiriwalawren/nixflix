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

  evalLidarr =
    extra:
    (evalConfig [
      {
        nixflix = {
          enable = true;
          lidarr = {
            enable = true;
            config = {
              apiKey._secret = "/run/lidarr-api-key";
              hostConfig.password._secret = "/run/lidarr-password";
            };
          };
        };
      }
      { nixflix = extra; }
    ]).config;

  units = {
    qualityProfiles = {
      unit = "lidarr-qualityprofiles";
      endpoint = "qualityprofile";
      deleteLog = "Deleting quality profile not in config";
    };
    metadataProfiles = {
      unit = "lidarr-metadataprofiles";
      endpoint = "metadataprofile";
      deleteLog = "Deleting metadata profile not in config";
    };
  };

  scriptOf = cfg: coll: cfg.systemd.services.${units.${coll}.unit}.script;
  modeOf = cfg: coll: cfg.nixflix.lidarr.syncMode.${coll};

  defaultCfg = evalLidarr { };
  globalKeep = evalLidarr { syncMode = "keep"; };
  globalRefuse = evalLidarr { syncMode = "refuse"; };
  perCollection = coll: mode: evalLidarr { lidarr.syncMode.${coll} = mode; };

  hasDelete = lib.hasInfix "-X DELETE";

  # Everything in the script before the refuse checkpoint.
  beforeCheckpoint = script: builtins.head (lib.splitString syncMode.refuseCheckpoint script);

  checkDefault =
    coll:
    let
      s = scriptOf defaultCfg coll;
    in
    modeOf defaultCfg coll == "delete"
    && lib.hasInfix units.${coll}.deleteLog s
    && hasDelete s
    && !(lib.hasInfix "# nixflix-sync-guard" s)
    && !(lib.hasInfix syncMode.refuseCheckpoint s);

  checkRefuse =
    cfg: coll:
    let
      s = scriptOf cfg coll;
    in
    modeOf cfg coll == "refuse"
    && guardPrecedesMutations s
    && lib.hasInfix syncMode.refuseCheckpoint s
    && !(hasDelete (beforeCheckpoint s))
    && !(lib.hasInfix units.${coll}.deleteLog s)
    && !(hasDelete s);

  checkKeep =
    cfg: coll:
    let
      s = scriptOf cfg coll;
    in
    modeOf cfg coll == "keep"
    && !(hasDelete s)
    && !(lib.hasInfix units.${coll}.deleteLog s)
    && lib.hasInfix "nixflix: ${units.${coll}.unit}: keeping " s
    && !(lib.hasInfix syncMode.refuseCheckpoint s);

  # Runs a rendered unit script with curl replaced by a stub: GETs return the
  # fixture, mutating calls ("-X METHOD") are logged as "METHOD URL".
  runUnit =
    name:
    {
      cfg,
      coll,
      live,
      checks,
    }:
    let
      stub = ''
        fake_curl() {
          method=GET url=
          while [ $# -gt 0 ]; do
            case "$1" in
              -X) method=$2; shift ;;
              *) url=$1 ;;
            esac
            shift
          done
          if [ "$method" = GET ]; then
            cat ${pkgs.writeText "${name}-live.json" (builtins.toJSON live)}
          else
            echo "$method $url" >> "$MUTATED_LOG"
            echo '{}'
          fi
        }
      '';
      script = builtins.replaceStrings [ "${pkgs.curl}/bin/curl" ] [ "fake_curl" ] (scriptOf cfg coll);
      scriptFile = pkgs.writeText "${name}.sh" (stub + script);
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export MUTATED_LOG=$PWD/mutated.log
      touch mutated.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt
      echo "--- mutations"; cat mutated.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  base = "http://127.0.0.1:8686/api/v1";

  qualityLive = [
    {
      id = 1;
      name = "Any";
    }
    {
      id = 2;
      name = "Lossless";
    }
    {
      id = 3;
      name = "Standard";
    }
  ];

  metadataLive = [
    {
      id = 1;
      name = "Standard";
    }
    {
      id = 2;
      name = "None";
    }
    {
      id = 3;
      name = "Extra";
    }
  ];
in
{
  sync-mode-lidarr-default-unchanged = assertTest "sync-mode-lidarr-default-unchanged" (
    checkDefault "qualityProfiles" && checkDefault "metadataProfiles"
  );

  sync-mode-lidarr-qualityprofiles-refuse = assertTest "sync-mode-lidarr-qualityprofiles-refuse" (
    checkRefuse (perCollection "qualityProfiles" "refuse") "qualityProfiles"
    && checkDefault "metadataProfiles"
  );

  sync-mode-lidarr-metadataprofiles-refuse = assertTest "sync-mode-lidarr-metadataprofiles-refuse" (
    checkRefuse (perCollection "metadataProfiles" "refuse") "metadataProfiles"
  );

  sync-mode-lidarr-qualityprofiles-keep = assertTest "sync-mode-lidarr-qualityprofiles-keep" (
    checkKeep (perCollection "qualityProfiles" "keep") "qualityProfiles"
  );

  sync-mode-lidarr-metadataprofiles-keep = assertTest "sync-mode-lidarr-metadataprofiles-keep" (
    checkKeep (perCollection "metadataProfiles" "keep") "metadataProfiles"
  );

  sync-mode-lidarr-global-propagates = assertTest "sync-mode-lidarr-global-propagates" (
    checkKeep globalKeep "qualityProfiles"
    && checkKeep globalKeep "metadataProfiles"
    && checkRefuse globalRefuse "qualityProfiles"
    && checkRefuse globalRefuse "metadataProfiles"
  );

  sync-mode-lidarr-override-beats-global =
    let
      cfg = evalLidarr {
        syncMode = "refuse";
        lidarr.syncMode = {
          qualityProfiles = "delete";
          metadataProfiles = "keep";
        };
      };
      q = scriptOf cfg "qualityProfiles";
    in
    assertTest "sync-mode-lidarr-override-beats-global" (
      modeOf cfg "qualityProfiles" == "delete"
      && q == scriptOf defaultCfg "qualityProfiles"
      && checkKeep cfg "metadataProfiles"
    );

  sync-mode-lidarr-option-not-in-config = assertTest "sync-mode-lidarr-option-not-in-config" (
    !(defaultCfg.nixflix.lidarr.config ? syncMode)
  );

  sync-mode-lidarr-qualityprofiles-run-refuse =
    runUnit "sync-mode-lidarr-qualityprofiles-run-refuse"
      {
        cfg = perCollection "qualityProfiles" "refuse";
        coll = "qualityProfiles";
        live = qualityLive;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          [ ! -s mutated.log ] || fail "refuse mutated"
          expectLine err.txt 'nixflix: lidarr-qualityprofiles: refusing to sync: 2 quality profiles exist that are not declared (nixflix.lidarr.syncMode.qualityProfiles = "refuse"). Nothing was changed.'
          expectLine err.txt 'nixflix:   - Lossless (id 2)'
          expectLine err.txt 'nixflix:   - Standard (id 3)'
          ! grep -q 'nixflix:   - Any ' err.txt || fail "declared profile listed"
          ! grep -q '/run/lidarr' out.txt err.txt || fail "secret path leaked"
        '';
      };

  sync-mode-lidarr-qualityprofiles-run-keep = runUnit "sync-mode-lidarr-qualityprofiles-run-keep" {
    cfg = perCollection "qualityProfiles" "keep";
    coll = "qualityProfiles";
    live = qualityLive;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q '^DELETE' mutated.log || fail "keep deleted something"
      expectLine mutated.log 'PUT ${base}/qualityprofile/1'
      expectLine out.txt 'nixflix: lidarr-qualityprofiles: keeping 2 undeclared quality profiles (nixflix.lidarr.syncMode.qualityProfiles = "keep"): Lossless, Standard'
    '';
  };

  sync-mode-lidarr-qualityprofiles-run-delete =
    runUnit "sync-mode-lidarr-qualityprofiles-run-delete"
      {
        cfg = defaultCfg;
        coll = "qualityProfiles";
        live = qualityLive;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          expectLine mutated.log 'DELETE ${base}/qualityprofile/2'
          expectLine mutated.log 'DELETE ${base}/qualityprofile/3'
          ! grep -qFx 'DELETE ${base}/qualityprofile/1' mutated.log || fail "deleted a declared profile"
          expectLine mutated.log 'PUT ${base}/qualityprofile/1'
        '';
      };

  # "None" is built in and undeletable, so it must not trip refuse.
  sync-mode-lidarr-metadataprofiles-run-refuse =
    runUnit "sync-mode-lidarr-metadataprofiles-run-refuse"
      {
        cfg = perCollection "metadataProfiles" "refuse";
        coll = "metadataProfiles";
        live = metadataLive;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          [ ! -s mutated.log ] || fail "refuse mutated"
          expectLine err.txt 'nixflix: lidarr-metadataprofiles: refusing to sync: 1 metadata profiles exist that are not declared (nixflix.lidarr.syncMode.metadataProfiles = "refuse"). Nothing was changed.'
          expectLine err.txt 'nixflix:   - Extra (id 3)'
          ! grep -q 'nixflix:   - None ' err.txt || fail "built-in None profile listed"
        '';
      };

  sync-mode-lidarr-metadataprofiles-run-refuse-none-only =
    runUnit "sync-mode-lidarr-metadataprofiles-run-refuse-none-only"
      {
        cfg = perCollection "metadataProfiles" "refuse";
        coll = "metadataProfiles";
        live = lib.take 2 metadataLive;
        checks = ''
          [ "$rc" = 0 ] || fail "built-in None blocked the sync, rc=$rc"
          expectLine mutated.log 'PUT ${base}/metadataprofile/1'
          ! grep -q '^DELETE' mutated.log || fail "refuse deleted something"
        '';
      };

  sync-mode-lidarr-metadataprofiles-run-keep = runUnit "sync-mode-lidarr-metadataprofiles-run-keep" {
    cfg = perCollection "metadataProfiles" "keep";
    coll = "metadataProfiles";
    live = metadataLive;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      ! grep -q '^DELETE' mutated.log || fail "keep deleted something"
      expectLine mutated.log 'PUT ${base}/metadataprofile/1'
      expectLine out.txt 'nixflix: lidarr-metadataprofiles: keeping 1 undeclared metadata profiles (nixflix.lidarr.syncMode.metadataProfiles = "keep"): Extra'
    '';
  };
}
