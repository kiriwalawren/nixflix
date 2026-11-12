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

  units = [
    "maintainerr-settings"
    "maintainerr-rules"
    "maintainerr-overlay-templates"
  ];

  baseModule = {
    nixflix = {
      enable = true;
      maintainerr = {
        enable = true;
        settings = {
          jellyfin.jellyfin_api_key = "jf-key";
          radarr = [
            {
              serverName = "Radarr";
              url = "http://radarr:7878";
              apiKey = "r-key";
            }
          ];
          sonarr = [
            {
              serverName = "Sonarr";
              url = "http://sonarr:8989";
              apiKey = "s-key";
            }
          ];
        };
        rules = [
          {
            name = "Old movies";
            library = "Movies";
            dataType = "movie";
          }
        ];
        overlays.templates = [
          {
            name = "Mine";
            mode = "poster";
            canvasWidth = 1000;
            canvasHeight = 1500;
          }
        ];
      };
    };
  };

  evalWith =
    nixflix:
    evalConfig [
      baseModule
      { inherit nixflix; }
    ];

  scriptsOf =
    cfg: lib.genAttrs units (u: cfg.config.systemd.services.${u}.serviceConfig.ExecStart.text);

  scriptsWith = nixflix: scriptsOf (evalWith nixflix);

  defaults = scriptsWith { };
  keepAll = scriptsWith { syncMode = "keep"; };
  refuseAll = scriptsWith { syncMode = "refuse"; };

  deleteLoops = {
    maintainerr-settings = [
      "Deleting undeclared radarr (id=$ID)"
      "Deleting undeclared sonarr (id=$ID)"
    ];
    maintainerr-rules = [ "Deleting undeclared rule group (id=$ID)" ];
    maintainerr-overlay-templates = [ "Deleting undeclared template (id=$ID)" ];
  };

  hasAll = needles: s: lib.all (n: lib.hasInfix n s) needles;
  hasNone = needles: s: !(lib.any (n: lib.hasInfix n s) needles);
  allUnits = pred: scripts: lib.all (u: pred u scripts.${u}) units;

  beforeCheckpoint = s: builtins.head (lib.splitString syncMode.refuseCheckpoint s);

  # Every Maintainerr call goes through this, so a unit's whole script can run
  # in the sandbox: GETs answer from $FIXTURES/<path with / as _>, anything else
  # is appended to $MUTATED_LOG and answered with a body every check accepts.
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET
    url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift 2 ;;
        -H|-d|--data-binary) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    path=''${url#http://*/}
    if [ "$method" = GET ]; then
      f="$FIXTURES/$(printf '%s' "$path" | tr / _)"
      if [ -e "$f" ]; then cat "$f"; else echo '[]'; fi
    else
      echo "$method /$path" >> "$MUTATED_LOG"
      echo '{"status":"OK","code":1,"id":5,"users":[{"id":"u1"}]}'
    fi
  '';

  curlPath = "${pkgs.curl}/bin/curl";

  withFakeCurl =
    script:
    assert lib.assertMsg (lib.hasInfix (builtins.unsafeDiscardStringContext curlPath) script)
      "unit script does not call ${curlPath}";
    builtins.replaceStrings [ curlPath ] [ "${fakeCurl}" ] script;

  # Runs one unit's real rendered script against fixture API responses, then
  # `checks` against $rc, out.txt, err.txt and mutated.log.
  runUnit =
    name:
    {
      scripts,
      unit,
      fixtures,
      checks,
    }:
    let
      fixtureDir = pkgs.linkFarm "fixtures-${name}" (
        lib.mapAttrsToList (n: v: {
          name = n;
          path = pkgs.writeText "fixture-${n}" (builtins.toJSON v);
        }) fixtures
      );
      scriptFile = pkgs.writeText "${name}.sh" (withFakeCurl scripts.${unit});
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export FIXTURES=${fixtureDir} MUTATED_LOG=$PWD/mutated.log
      touch mutated.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt
      echo "--- mutations"; cat mutated.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      mutated() { grep -qFx -- "$1" mutated.log || fail "missing mutation: $1"; }
      notMutated() { ! grep -qFx -- "$1" mutated.log || fail "unexpected mutation: $1"; }
      noDeletes() { ! grep -q '^DELETE ' mutated.log || fail "deleted something"; }
      noLeak() { ! grep -q LIVESECRET out.txt err.txt || fail "object contents leaked"; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  settingsFixtures = {
    api_settings = {
      media_server_type = "jellyfin";
    };
    api_settings_radarr = [
      {
        id = 1;
        serverName = "Radarr";
        apiKey = "LIVESECRET";
      }
      {
        id = 2;
        serverName = "Old Radarr";
        url = "http://old:7878";
        apiKey = "LIVESECRET";
      }
    ];
    api_settings_sonarr = [
      {
        id = 3;
        serverName = "Sonarr";
      }
    ];
  };

  rulesFixtures = {
    api_settings.media_server_type = "jellyfin";
    api_rules = [
      {
        id = 10;
        name = "Old movies";
      }
      {
        id = 11;
        name = "Stray";
        description = "LIVESECRET";
      }
    ];
    api_media-server_libraries = [
      {
        id = "m1";
        title = "Movies";
      }
    ];
  };

  templatesFixtures = {
    api_overlays_templates = [
      {
        id = 1;
        name = "Classic Pill";
        isPreset = true;
      }
      {
        id = 2;
        name = "Title Card Pill";
        isPreset = true;
      }
      {
        id = 3;
        name = "Mine";
        isPreset = false;
      }
      {
        id = 4;
        name = "Stray";
        isPreset = false;
        elements = [ "LIVESECRET" ];
      }
    ];
  };

  # Maintainerr still set up for Plex, with data a switch to Jellyfin clears.
  # Every *arr server is declared, so only the switch decides the outcome.
  switchFixtures =
    {
      type ? "plex",
      clears ? true,
    }:
    {
      api_settings.media_server_type = type;
      api_settings_radarr = [
        {
          id = 1;
          serverName = "Radarr";
        }
      ];
      api_settings_sonarr = [
        {
          id = 3;
          serverName = "Sonarr";
        }
      ];
      api_settings_media-server_switch_preview_jellyfin.dataToBeCleared = {
        collections = if clears then 2 else 0;
        collectionMedia = 0;
        exclusions = if clears then 1 else 0;
        collectionLogs = 0;
      };
      api_rules =
        if clears then
          [
            {
              id = 10;
              name = "Old movies";
            }
            {
              id = 11;
              name = "Plex only";
            }
          ]
        else
          [ ];
    };
  switchCall = "POST /api/settings/media-server/switch";
  clearsText = "2 rule groups (with their rules), 2 collections, 1 exclusions";
in
{
  sync-mode-maintainerr-options-inherit-global =
    let
      modesFor = nixflix: (evalWith nixflix).config.nixflix.maintainerr.syncMode;
      all =
        mode: m:
        m == {
          radarr = mode;
          sonarr = mode;
          rules = mode;
          overlayTemplates = mode;
          mediaServer = mode;
        };
    in
    assertTest "sync-mode-maintainerr-options-inherit-global" (
      all "delete" (modesFor { })
      && all "keep" (modesFor {
        syncMode = "keep";
      })
      && all "refuse" (modesFor {
        syncMode = "refuse";
      })
      &&
        (modesFor {
          syncMode = "refuse";
          maintainerr.syncMode.rules = "delete";
        }).rules == "delete"
    );

  # Default mode keeps every original delete loop and adds no sync-mode code.
  # Byte-for-byte equality with upstream is sync-mode-coverage-delete-matches-upstream.
  sync-mode-maintainerr-default-unchanged = assertTest "sync-mode-maintainerr-default-unchanged" (
    allUnits (
      u: s:
      hasAll deleteLoops.${u} s && hasNone [ "# nixflix-sync-guard" "NIXFLIX_SYNC_REFUSED" "keeping" ] s
    ) defaults
  );

  sync-mode-maintainerr-refuse-guards-first = assertTest "sync-mode-maintainerr-refuse-guards-first" (
    allUnits (
      _: s:
      guardPrecedesMutations s
      && lib.hasInfix syncMode.refuseCheckpoint s
      && !(lib.hasInfix "-X" (beforeCheckpoint s))
      && !(lib.hasInfix "-X DELETE" s)
    ) refuseAll
    && hasAll [
      "# nixflix-sync-guard: maintainerr-settings radarr servers"
      "# nixflix-sync-guard: maintainerr-settings sonarr servers"
    ] refuseAll.maintainerr-settings
    # The guards must come before the Jellyfin/Seerr settings are applied.
    && !(lib.hasInfix "Switching media server type" (beforeCheckpoint refuseAll.maintainerr-settings))
  );

  sync-mode-maintainerr-keep-no-deletes = assertTest "sync-mode-maintainerr-keep-no-deletes" (
    allUnits (
      _: s:
      !(lib.hasInfix "-X DELETE" s)
      && lib.hasInfix "keeping" s
      && !(lib.hasInfix "# nixflix-sync-guard" s)
    ) keepAll
  );

  sync-mode-maintainerr-override-beats-global =
    let
      mixed = scriptsWith {
        syncMode = "refuse";
        maintainerr.syncMode = {
          radarr = "delete";
          rules = "delete";
        };
      };
      onlyTemplates = scriptsWith { maintainerr.syncMode.overlayTemplates = "refuse"; };
      s = mixed.maintainerr-settings;
    in
    assertTest "sync-mode-maintainerr-override-beats-global" (
      # rules forced back to delete under a global refuse
      hasAll deleteLoops.maintainerr-rules mixed.maintainerr-rules
      && !(lib.hasInfix "# nixflix-sync-guard" mixed.maintainerr-rules)
      # radarr deletes, sonarr refuses, in the same unit
      && lib.hasInfix "Deleting undeclared radarr" s
      && !(lib.hasInfix "Deleting undeclared sonarr" s)
      && lib.hasInfix "# nixflix-sync-guard: maintainerr-settings sonarr servers" s
      && !(lib.hasInfix "# nixflix-sync-guard: maintainerr-settings radarr servers" s)
      && guardPrecedesMutations s
      # templates inherit the global refuse
      && guardPrecedesMutations mixed.maintainerr-overlay-templates
      # a single per-collection refuse under the default global
      && guardPrecedesMutations onlyTemplates.maintainerr-overlay-templates
      && hasAll deleteLoops.maintainerr-rules onlyTemplates.maintainerr-rules
      && onlyTemplates.maintainerr-settings == defaults.maintainerr-settings
      && onlyTemplates.maintainerr-rules == defaults.maintainerr-rules
    );

  sync-mode-maintainerr-settings-delete-run = runUnit "sync-mode-maintainerr-settings-delete-run" {
    scripts = defaults;
    unit = "maintainerr-settings";
    fixtures = settingsFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      mutated "DELETE /api/settings/radarr/2"
      notMutated "DELETE /api/settings/radarr/1"
      notMutated "DELETE /api/settings/sonarr/3"
      mutated "PUT /api/settings/radarr/1"
      mutated "PUT /api/settings/sonarr/3"
    '';
  };

  sync-mode-maintainerr-settings-keep-run = runUnit "sync-mode-maintainerr-settings-keep-run" {
    scripts = keepAll;
    unit = "maintainerr-settings";
    fixtures = settingsFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      noDeletes
      noLeak
      mutated "PUT /api/settings/radarr/1"
      mutated "PUT /api/settings/sonarr/3"
      mutated "PATCH /api/settings"
      expectLine out.txt 'nixflix: maintainerr-settings: keeping 1 undeclared radarr servers (nixflix.maintainerr.syncMode.radarr = "keep"): Old Radarr'
    '';
  };

  sync-mode-maintainerr-settings-refuse-run = runUnit "sync-mode-maintainerr-settings-refuse-run" {
    scripts = refuseAll;
    unit = "maintainerr-settings";
    fixtures = settingsFixtures;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s mutated.log ] || fail "refuse let the unit mutate"
      noLeak
      ! grep -q 'http://old' out.txt err.txt || fail "url leaked"
      expectLine err.txt 'nixflix: maintainerr-settings: refusing to sync: 1 radarr servers exist that are not declared (nixflix.maintainerr.syncMode.radarr = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - Old Radarr (id 2)'
      ! grep -q 'sonarr servers exist' err.txt || fail "sonarr reported though fully declared"
    '';
  };

  sync-mode-maintainerr-settings-refuse-declared-run =
    runUnit "sync-mode-maintainerr-settings-refuse-declared-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-settings";
        fixtures = settingsFixtures // {
          api_settings_radarr = [
            {
              id = 1;
              serverName = "Radarr";
            }
          ];
        };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          noDeletes
          mutated "PUT /api/settings/radarr/1"
          mutated "PATCH /api/settings"
        '';
      };

  sync-mode-maintainerr-rules-delete-run = runUnit "sync-mode-maintainerr-rules-delete-run" {
    scripts = defaults;
    unit = "maintainerr-rules";
    fixtures = rulesFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      mutated "PUT /api/rules"
      mutated "DELETE /api/rules/11"
      notMutated "DELETE /api/rules/10"
    '';
  };

  sync-mode-maintainerr-rules-keep-run = runUnit "sync-mode-maintainerr-rules-keep-run" {
    scripts = keepAll;
    unit = "maintainerr-rules";
    fixtures = rulesFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      noDeletes
      noLeak
      mutated "PUT /api/rules"
      expectLine out.txt 'nixflix: maintainerr-rules: keeping 1 undeclared rule groups (nixflix.maintainerr.syncMode.rules = "keep"): Stray'
    '';
  };

  sync-mode-maintainerr-rules-refuse-run = runUnit "sync-mode-maintainerr-rules-refuse-run" {
    scripts = refuseAll;
    unit = "maintainerr-rules";
    fixtures = rulesFixtures;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s mutated.log ] || fail "refuse let the unit mutate"
      noLeak
      expectLine err.txt 'nixflix:   - Stray (id 11)'
      ! grep -q 'Old movies' err.txt || fail "declared rule listed"
    '';
  };

  sync-mode-maintainerr-templates-delete-run = runUnit "sync-mode-maintainerr-templates-delete-run" {
    scripts = defaults;
    unit = "maintainerr-overlay-templates";
    fixtures = templatesFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      mutated "PUT /api/overlays/templates/3"
      mutated "DELETE /api/overlays/templates/4"
      [ "$(grep -c '^DELETE ' mutated.log)" = 1 ] || fail "deleted more than the stray template"
    '';
  };

  sync-mode-maintainerr-templates-keep-run = runUnit "sync-mode-maintainerr-templates-keep-run" {
    scripts = keepAll;
    unit = "maintainerr-overlay-templates";
    fixtures = templatesFixtures;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      noDeletes
      noLeak
      mutated "PUT /api/overlays/templates/3"
      expectLine out.txt 'nixflix: maintainerr-overlay-templates: keeping 1 undeclared overlay templates (nixflix.maintainerr.syncMode.overlayTemplates = "keep"): Stray'
    '';
  };

  sync-mode-maintainerr-templates-refuse-run = runUnit "sync-mode-maintainerr-templates-refuse-run" {
    scripts = refuseAll;
    unit = "maintainerr-overlay-templates";
    fixtures = templatesFixtures;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s mutated.log ] || fail "refuse let the unit mutate"
      noLeak
      expectLine err.txt 'nixflix:   - Stray (id 4)'
      ! grep -qE 'Pill|Mine' err.txt || fail "preset or declared template listed"
    '';
  };

  # Presets are always live and can never be deleted; they must not block refuse.
  sync-mode-maintainerr-templates-refuse-presets-run =
    runUnit "sync-mode-maintainerr-templates-refuse-presets-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-overlay-templates";
        fixtures.api_overlays_templates = lib.take 3 templatesFixtures.api_overlays_templates;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          noDeletes
          mutated "PUT /api/overlays/templates/3"
        '';
      };

  sync-mode-maintainerr-switch-delete-run = runUnit "sync-mode-maintainerr-switch-delete-run" {
    scripts = defaults;
    unit = "maintainerr-settings";
    fixtures = switchFixtures { };
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      mutated ${lib.escapeShellArg switchCall}
    '';
  };

  sync-mode-maintainerr-switch-keep-run = runUnit "sync-mode-maintainerr-switch-keep-run" {
    scripts = keepAll;
    unit = "maintainerr-settings";
    fixtures = switchFixtures { };
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      notMutated ${lib.escapeShellArg switchCall}
      expectLine out.txt ${lib.escapeShellArg "nixflix: maintainerr-settings: not switching media server 'plex' to Jellyfin: that clears ${clearsText} (nixflix.maintainerr.syncMode.mediaServer = \"keep\")"}
      # The rest of the unit still syncs declared settings, but not Jellyfin's.
      mutated "PUT /api/settings/radarr/1"
      notMutated "POST /api/settings/jellyfin/test"
      notMutated "POST /api/settings/jellyfin"
      expectLine out.txt ${lib.escapeShellArg "nixflix: maintainerr-settings: Maintainerr stays on media server 'plex', so the Jellyfin connection is not set up (nixflix.maintainerr.syncMode.mediaServer = \"keep\")"}
    '';
  };

  sync-mode-maintainerr-switch-refuse-run = runUnit "sync-mode-maintainerr-switch-refuse-run" {
    scripts = refuseAll;
    unit = "maintainerr-settings";
    fixtures = switchFixtures { };
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s mutated.log ] || fail "refuse let the unit mutate"
      expectLine err.txt ${lib.escapeShellArg "nixflix: maintainerr-settings: refusing to sync: Maintainerr uses media server 'plex', and switching it to Jellyfin clears ${clearsText} (nixflix.maintainerr.syncMode.mediaServer = \"refuse\"). Nothing was changed."}
    '';
  };

  # A switch that clears nothing (empty Plex setup, or a fresh install with no
  # media server yet) happens in every mode.
  sync-mode-maintainerr-switch-refuse-empty-run =
    runUnit "sync-mode-maintainerr-switch-refuse-empty-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-settings";
        fixtures = switchFixtures { clears = false; };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          mutated ${lib.escapeShellArg switchCall}
        '';
      };

  sync-mode-maintainerr-switch-keep-fresh-run =
    runUnit "sync-mode-maintainerr-switch-keep-fresh-run"
      {
        scripts = keepAll;
        unit = "maintainerr-settings";
        fixtures = switchFixtures {
          type = null;
          clears = false;
        };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          mutated ${lib.escapeShellArg switchCall}
          mutated "POST /api/settings/jellyfin"
        '';
      };

  sync-mode-maintainerr-switch-jellyfin-refuse-run =
    runUnit "sync-mode-maintainerr-switch-jellyfin-refuse-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-settings";
        fixtures = switchFixtures { type = "jellyfin"; };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          notMutated ${lib.escapeShellArg switchCall}
        '';
      };

  # A preview that is not the expected object fails the unit before any change.
  sync-mode-maintainerr-switch-refuse-bad-preview-run =
    runUnit "sync-mode-maintainerr-switch-refuse-bad-preview-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-settings";
        fixtures = switchFixtures { } // {
          api_settings_media-server_switch_preview_jellyfin = {
            message = "Unauthorized";
          };
        };
        checks = ''
          [ "$rc" != 0 ] && [ "$rc" != 78 ] || fail "expected a non-refusal failure, got rc $rc"
          [ ! -s mutated.log ] || fail "mutated after a bad preview"
        '';
      };

  sync-mode-maintainerr-switch-override-run = runUnit "sync-mode-maintainerr-switch-override-run" {
    scripts = scriptsWith {
      syncMode = "refuse";
      maintainerr.syncMode.mediaServer = "delete";
    };
    unit = "maintainerr-settings";
    fixtures = switchFixtures { };
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      mutated ${lib.escapeShellArg switchCall}
    '';
  };

  # maintainerr-rules asks Maintainerr which media server it uses and, outside
  # delete mode, skips when it is not Jellyfin (keep left it on Plex).
  sync-mode-maintainerr-rules-keep-on-plex-run =
    runUnit "sync-mode-maintainerr-rules-keep-on-plex-run"
      {
        scripts = keepAll;
        unit = "maintainerr-rules";
        fixtures = rulesFixtures // {
          api_settings.media_server_type = "plex";
        };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ ! -s mutated.log ] || fail "rules synced into a Plex Maintainerr"
          expectLine out.txt ${lib.escapeShellArg "nixflix: maintainerr-rules: Maintainerr uses media server 'plex', not Jellyfin; rule groups are not synced (nixflix.maintainerr.syncMode.mediaServer = \"keep\")"}
        '';
      };

  sync-mode-maintainerr-rules-refuse-on-plex-run =
    runUnit "sync-mode-maintainerr-rules-refuse-on-plex-run"
      {
        scripts = refuseAll;
        unit = "maintainerr-rules";
        fixtures = rulesFixtures // {
          api_settings.media_server_type = "plex";
        };
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ ! -s mutated.log ] || fail "rules synced into a Plex Maintainerr"
        '';
      };

  # delete always switched first, so it does not ask (and is upstream's text).
  sync-mode-maintainerr-rules-delete-no-gate =
    assertTest "sync-mode-maintainerr-rules-delete-no-gate"
      (
        !lib.hasInfix "rule groups are not synced" defaults.maintainerr-rules
        && lib.hasInfix "rule groups are not synced" keepAll.maintainerr-rules
      );
}
