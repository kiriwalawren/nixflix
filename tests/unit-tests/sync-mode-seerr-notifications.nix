# nixflix.seerr.syncMode.notifications: seerr-notifications switches off every
# Seerr notification agent nixflix.notif does not target. The real unit
# script runs against a fake Seerr API in each mode.
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

  webhookSecret = pkgs.writeText "discord-webhook" "https://discord.example/DECLARED-SECRET";

  scriptFor =
    settings:
    let
      evaluated = evalConfig [
        {
          nixflix = lib.recursiveUpdate {
            enable = true;
            jellyfin = {
              enable = true;
              apiKey = "jellyfin-key";
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
            seerr = {
              enable = true;
              apiKey = "seerr-key";
            };
            notif.discord = {
              webHookUrl._secret = webhookSecret;
              seerr.enable = true;
            };
          } settings;
        }
      ];
    in
    {
      script = evaluated.config.systemd.services.seerr-notifications.script;
      inherit (evaluated) pkgs;
    };

  defaults = scriptFor { };
  keep = scriptFor { syncMode = "keep"; };
  refuse = scriptFor { syncMode = "refuse"; };

  # GET .../notifications/<agent> answers $FIXTURES/<agent>.json (or a
  # disabled agent); every POST is logged as "POST <agent> <body>".
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET url="" data="" wfmt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift 2 ;;
        -d) data=$2; shift 2 ;;
        -w) wfmt=$2; shift 2 ;;
        --variable | --expand-header | --header | --max-time) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    if [ "$data" = "@-" ]; then data=$(cat); fi
    agent=''${url##*/}
    if [ "$method" = GET ]; then
      if [ -e "$FIXTURES/$agent.json" ]; then cat "$FIXTURES/$agent.json"; else echo '{"enabled":false,"options":{}}'; fi
    else
      printf '%s %s %s\n' "$method" "$agent" "$(printf '%s' "$data" | ${pkgs.jq}/bin/jq -cS .)" >> "$CURL_LOG"
      printf '{}'
      [ -z "$wfmt" ] || printf '\n200'
    fi
  '';

  # slack is enabled in Seerr with a secret in its options; nixflix only
  # targets discord.
  fixtures = pkgs.linkFarm "seerr-notifications-fixtures" [
    {
      name = "slack.json";
      path = pkgs.writeText "slack.json" (
        builtins.toJSON {
          enabled = true;
          options.webhookUrl = "https://hooks.slack.example/LIVE-SECRET";
        }
      );
    }
    {
      name = "discord.json";
      path = pkgs.writeText "discord.json" (
        builtins.toJSON {
          enabled = false;
          options = { };
        }
      );
    }
  ];

  run =
    name: r: checks:
    let
      scriptFile = pkgs.writeText "${name}.sh" (
        builtins.replaceStrings [ "${r.pkgs.curl}/bin/curl" ] [ "${fakeCurl}" ] r.script
      );
    in
    pkgs.runCommand "unit-test-${name}" { nativeBuildInputs = [ pkgs.jq ]; } ''
      export FIXTURES=${fixtures} CURL_LOG=$PWD/curl.log
      touch curl.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt; echo "--- curl"; cat curl.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      ! grep -qE 'LIVE-SECRET|DECLARED-SECRET' out.txt err.txt || fail "an agent's options leaked into the log"
      ${checks}
      echo 'PASS: ${name}' > $out
    '';
in
{
  sync-mode-seerr-notifications-options = assertTest "sync-mode-seerr-notifications-options" (
    let
      modeOf =
        s:
        (evalConfig [
          {
            nixflix = {
              enable = true;
              syncMode = s;
            };
          }
        ]).config.nixflix.seerr.syncMode.notifications;
    in
    modeOf "delete" == "delete" && modeOf "keep" == "keep" && modeOf "refuse" == "refuse"
  );

  sync-mode-seerr-notifications-refuse-guard-first =
    assertTest "sync-mode-seerr-notifications-refuse-guard-first"
      (
        guardPrecedesMutations refuse.script
        && lib.hasInfix syncMode.refuseCheckpoint refuse.script
        && !lib.hasInfix "nixflix-sync-guard" defaults.script
        && !lib.hasInfix "nixflix-sync-guard" keep.script
      );

  sync-mode-seerr-notifications-delete-run =
    run "sync-mode-seerr-notifications-delete-run" defaults
      ''
        [ "$rc" = 0 ] || fail "rc=$rc"
        grep -q '^POST discord .*"enabled":true' curl.log || fail "discord not configured"
        grep -q '^POST slack .*"enabled":false' curl.log || fail "untargeted slack not disabled"
      '';

  sync-mode-seerr-notifications-keep-run = run "sync-mode-seerr-notifications-keep-run" keep ''
    [ "$rc" = 0 ] || fail "rc=$rc"
    grep -q '^POST discord .*"enabled":true' curl.log || fail "discord not configured"
    ! grep -q '^POST slack' curl.log || fail "keep disabled slack"
    grep -q 'DECLARED-SECRET' curl.log || fail "declared webhook secret not resolved into the POST"
    expectLine out.txt 'nixflix: seerr-notifications: keeping 1 undeclared enabled Seerr notification agents (nixflix.seerr.syncMode.notifications = "keep"): slack'
  '';

  sync-mode-seerr-notifications-refuse-run = run "sync-mode-seerr-notifications-refuse-run" refuse ''
    [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
    [ ! -s curl.log ] || fail "refuse posted: $(cat curl.log)"
    expectLine err.txt 'nixflix:   - slack (id slack)'
  '';
}
