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

  category = name: {
    inherit name;
    dir = name;
    priority = 0;
    pp = 3;
    script = "None";
  };

  sabnzbdConfig =
    nixflix:
    (evalConfig [
      {
        nixflix = lib.recursiveUpdate {
          enable = true;
          usenetClients.sabnzbd = {
            enable = true;
            settings = {
              misc = {
                api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey";
                nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey";
                url_base = "/sabnzbd";
              };
              categories = [
                (category "radarr")
                (category "*")
              ];
            };
          };
        } nixflix;
      }
    ]).config;

  sabnzbdScript = nixflix: (sabnzbdConfig nixflix).systemd.services.sabnzbd-categories.script;
  sabnzbdMode = nixflix: (sabnzbdConfig nixflix).nixflix.usenetClients.sabnzbd.syncMode.categories;

  qbittorrentConfig =
    nixflix:
    (evalConfig [
      {
        nixflix = lib.recursiveUpdate {
          enable = true;
          torrentClients.qbittorrent = {
            enable = true;
            password._secret = pkgs.writeText "qbittorrent-password" "pw";
            categories = {
              radarr = "/data/torrent/radarr";
              sonarr = "/data/torrent/sonarr";
            };
          };
        } nixflix;
      }
    ]).config;

  qbittorrentPreStart = nixflix: (qbittorrentConfig nixflix).systemd.services.qbittorrent.preStart;
  qbittorrentMode =
    nixflix: (qbittorrentConfig nixflix).nixflix.torrentClients.qbittorrent.syncMode.categories;

  before =
    needle: other: text:
    let
      head = s: builtins.head (builtins.split (lib.escapeRegex s) text);
    in
    lib.hasInfix needle text && lib.stringLength (head needle) < lib.stringLength (head other);

  sabRefuse = sabnzbdScript { usenetClients.sabnzbd.syncMode.categories = "refuse"; };
  sabKeep = sabnzbdScript { usenetClients.sabnzbd.syncMode.categories = "keep"; };
  qbRefuse = qbittorrentPreStart { torrentClients.qbittorrent.syncMode.categories = "refuse"; };
  qbKeep = qbittorrentPreStart { torrentClients.qbittorrent.syncMode.categories = "keep"; };

  # Runs the rendered sabnzbd-categories script against a fake SABnzbd API.
  # `curl` is a shell function that answers get_config with $GET_CONFIG and
  # logs every other call (minus the API key) to calls.log. Like curl's
  # config parser, it ends an unquoted url at the first whitespace.
  runSabnzbd =
    name:
    {
      mode,
      getConfig,
      checks,
      categories ? null,
    }:
    let
      script = sabnzbdScript (
        lib.recursiveUpdate { usenetClients.sabnzbd.syncMode.categories = mode; } (
          lib.optionalAttrs (categories != null) {
            usenetClients.sabnzbd.settings.categories = map category categories;
          }
        )
      );
      scriptFile = pkgs.writeText "${name}.sh" ''
        curl() {
          local url
          url=$(sed -n 's/^url = //p')
          url=''${url%%[[:space:]]*}
          case "$url" in
            *mode=version*) echo '{"version":"4.0.0"}' ;;
            *mode=get_config*) cat ${pkgs.writeText "${name}-get-config.json" (builtins.toJSON getConfig)} ;;
            *) printf '%s\n' "$url" | sed 's/.*[?]mode=//; s/&apikey=[^&]*//' >> "$CALLS_LOG"; echo '{"status":true}' ;;
          esac
        }
        ${script}
      '';
    in
    pkgs.runCommand "unit-test-${name}"
      {
        nativeBuildInputs = with pkgs; [
          jq
          gnugrep
          gnused
          coreutils
        ];
      }
      ''
        export CALLS_LOG=$PWD/calls.log
        touch calls.log
        rc=0
        ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
        echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt; echo "--- calls"; cat calls.log

        fail() { echo "FAIL: ${name}: $*"; exit 1; }
        expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
        deletes() { grep '^del_config' calls.log | sed 's/.*&keyword=//' | sort | tr '\n' '|'; }
        ${checks}
        echo 'PASS: ${name}' > $out
      '';

  liveCategories = {
    config.categories = [
      {
        name = "*";
        order = 0;
      }
      {
        name = "radarr";
        order = 1;
      }
      {
        name = "my movies";
        order = 2;
      }
      {
        name = "tv";
        order = 3;
      }
    ];
  };

  # Declared names that are regex metacharacters, a grep option and a case
  # difference, against SABnzbd's lowercased live copy.
  trickyDeclared = [
    "radarr"
    "[tv]"
    "-x"
    "Books"
    "abc"
  ];
  trickyLive.config.categories = lib.imap0 (order: name: { inherit name order; }) [
    "*"
    "radarr"
    "[tv]"
    "-x"
    "books"
    "abc"
    "a.c"
    "old"
  ];

  # Runs the rendered qbittorrent preStart against a categories.json in the
  # build directory. `existing` is the file's raw text, or null for no file.
  runQbittorrent =
    name:
    {
      mode,
      existing,
      checks,
    }:
    let
      config = qbittorrentConfig { torrentClients.qbittorrent.syncMode.categories = mode; };
      configPath = "${config.services.qbittorrent.profileDir}/qBittorrent/config";
      preStart =
        builtins.replaceStrings [ configPath ] [ "'\"$QB_CONFIG\"'" ]
          config.systemd.services.qbittorrent.preStart;
      scriptFile = pkgs.writeText "${name}.sh" ''
        set -e
        chown() { :; }
        ${preStart}
      '';
    in
    pkgs.runCommand "unit-test-${name}" { nativeBuildInputs = [ pkgs.jq ]; } ''
      export QB_CONFIG=$PWD/config
      mkdir config
      ${lib.optionalString (existing != null)
        "cp ${pkgs.writeText "${name}-existing.json" existing} config/categories.json; chmod 644 config/categories.json"
      }
      ${lib.optionalString (existing != null) "cp config/categories.json before.json"}
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt
      echo "--- categories.json"; cat config/categories.json 2>/dev/null || echo '(none)'

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      result() { jq -cS . config/categories.json; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  declaredQb = ''{"radarr":{"save_path":"/data/torrent/radarr"},"sonarr":{"save_path":"/data/torrent/sonarr"}}'';
  existingQb = builtins.toJSON {
    radarr.save_path = "/old/radarr";
    manual.save_path = "/data/torrent/manual";
    "with space".save_path = "/x";
  };
in
{
  # --- SABnzbd ---------------------------------------------------------------

  sync-mode-dlclients-sabnzbd-default-deletes =
    let
      script = sabnzbdScript { };
    in
    assertTest "sync-mode-dlclients-sabnzbd-default-deletes" (
      sabnzbdMode { } == "delete"
      && lib.hasInfix ''echo "Removing categories not in configuration..."'' script
      && lib.hasInfix ''"keyword=$(jq -rn --arg c "$existing_cat" '$c | @uri')"'' script
      && lib.hasInfix ''done <<< "$EXISTING_CATEGORIES"'' script
      && !lib.hasInfix "nixflix-sync-guard" script
      && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" script
    );

  sync-mode-dlclients-sabnzbd-refuse-guards = assertTest "sync-mode-dlclients-sabnzbd-refuse-guards" (
    guardPrecedesMutations sabRefuse
    && lib.hasInfix syncMode.refuseCheckpoint sabRefuse
    && before syncMode.refuseCheckpoint "set_config" sabRefuse
    && !lib.hasInfix "del_config" sabRefuse
  );

  sync-mode-dlclients-sabnzbd-keep-never-deletes =
    assertTest "sync-mode-dlclients-sabnzbd-keep-never-deletes"
      (
        !lib.hasInfix "del_config" sabKeep
        && lib.hasInfix "keeping " sabKeep
        && !lib.hasInfix "nixflix-sync-guard" sabKeep
      );

  sync-mode-dlclients-sabnzbd-override-beats-global =
    assertTest "sync-mode-dlclients-sabnzbd-override-beats-global"
      (
        sabnzbdMode { syncMode = "keep"; } == "keep"
        && sabnzbdMode { syncMode = "refuse"; } == "refuse"
        && guardPrecedesMutations (sabnzbdScript {
          syncMode = "refuse";
        })
        && !lib.hasInfix "del_config" (sabnzbdScript {
          syncMode = "keep";
        })
        &&
          sabnzbdScript {
            syncMode = "refuse";
            usenetClients.sabnzbd.syncMode.categories = "delete";
          } == sabnzbdScript { }
        && guardPrecedesMutations (sabnzbdScript {
          syncMode = "keep";
          usenetClients.sabnzbd.syncMode.categories = "refuse";
        })
      );

  # Regression: `for existing_cat in $EXISTING_CATEGORIES` split "my movies"
  # into "my" and "movies" and glob-expanded "*" into file names, and the
  # unencoded keyword was cut at the space by curl.
  sync-mode-dlclients-sabnzbd-delete-names-with-spaces =
    runSabnzbd "sync-mode-dlclients-sabnzbd-delete-names-with-spaces"
      {
        mode = "delete";
        getConfig = liveCategories;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(deletes)" = "my%20movies|tv|" ] || fail "deleted: $(deletes)"
          grep -q '^set_config&section=categories&.*name=radarr' calls.log || fail "radarr not configured"
          expectLine out.txt 'Deleting category not in config: my movies'
        '';
      };

  sync-mode-dlclients-sabnzbd-keep-run = runSabnzbd "sync-mode-dlclients-sabnzbd-keep-run" {
    mode = "keep";
    getConfig = liveCategories;
    checks = ''
      [ "$rc" = 0 ] || fail "rc=$rc"
      [ -z "$(deletes)" ] || fail "keep deleted: $(deletes)"
      grep -q '^set_config&section=categories&.*name=radarr' calls.log || fail "radarr not configured"
      expectLine out.txt 'nixflix: sabnzbd-categories: keeping 2 undeclared categories (nixflix.usenetClients.sabnzbd.syncMode.categories = "keep"): my movies, tv'
      ! grep -q testapikey out.txt err.txt || fail "api key leaked"
    '';
  };

  sync-mode-dlclients-sabnzbd-refuse-run = runSabnzbd "sync-mode-dlclients-sabnzbd-refuse-run" {
    mode = "refuse";
    getConfig = liveCategories;
    checks = ''
      [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
      [ ! -s calls.log ] || fail "refuse mutated SABnzbd"
      expectLine err.txt 'nixflix: sabnzbd-categories: refusing to sync: 2 categories exist that are not declared (nixflix.usenetClients.sabnzbd.syncMode.categories = "refuse"). Nothing was changed.'
      expectLine err.txt 'nixflix:   - my movies (id 2)'
      expectLine err.txt 'nixflix:   - tv (id 3)'
      ! grep -q 'nixflix:   - \*' err.txt || fail "built-in * listed"
      ! grep -q testapikey out.txt err.txt || fail "api key leaked"
    '';
  };

  # "*" is ignored even when the declared list leaves it out, so refuse can
  # pass. Real SABnzbd always returns "*", so this fails without `ignore`.
  sync-mode-dlclients-sabnzbd-refuse-all-declared =
    runSabnzbd "sync-mode-dlclients-sabnzbd-refuse-all-declared"
      {
        mode = "refuse";
        categories = [ "radarr" ];
        getConfig.config.categories = [
          {
            name = "*";
            order = 0;
          }
          {
            name = "radarr";
            order = 1;
          }
        ];
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ -z "$(deletes)" ] || fail "deleted: $(deletes)"
          grep -q '^set_config&section=categories&.*name=radarr' calls.log || fail "sync did not proceed"
        '';
      };

  sync-mode-dlclients-sabnzbd-keep-ignores-star =
    runSabnzbd "sync-mode-dlclients-sabnzbd-keep-ignores-star"
      {
        mode = "keep";
        categories = [ "radarr" ];
        getConfig.config.categories = [
          {
            name = "*";
            order = 0;
          }
          {
            name = "radarr";
            order = 1;
          }
        ];
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          ! grep -q keeping out.txt || fail "keep listed the built-in *"
        '';
      };

  # Regression: the delete loop matched the live name as a case-sensitive
  # regex (`grep -qx "$existing_cat"`). SABnzbd stores names lowercased, so a
  # declared "Books" (live "books") was deleted and re-created on every run;
  # "[tv]" was a character class and "-x" a grep option, so both were deleted
  # although declared; "a.c" matched the declared "abc" and was kept although
  # undeclared. refuse and keep must agree with delete on every one of them.
  sync-mode-dlclients-sabnzbd-delete-fixed-string-names =
    runSabnzbd "sync-mode-dlclients-sabnzbd-delete-fixed-string-names"
      {
        mode = "delete";
        categories = trickyDeclared;
        getConfig = trickyLive;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(deletes)" = "a.c|old|" ] || fail "deleted: $(deletes)"
        '';
      };

  sync-mode-dlclients-sabnzbd-refuse-fixed-string-names =
    runSabnzbd "sync-mode-dlclients-sabnzbd-refuse-fixed-string-names"
      {
        mode = "refuse";
        categories = trickyDeclared;
        getConfig = trickyLive;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          [ ! -s calls.log ] || fail "refuse mutated SABnzbd"
          expectLine err.txt 'nixflix: sabnzbd-categories: refusing to sync: 2 categories exist that are not declared (nixflix.usenetClients.sabnzbd.syncMode.categories = "refuse"). Nothing was changed.'
          expectLine err.txt 'nixflix:   - a.c (id 6)'
          expectLine err.txt 'nixflix:   - old (id 7)'
        '';
      };

  sync-mode-dlclients-sabnzbd-keep-fixed-string-names =
    runSabnzbd "sync-mode-dlclients-sabnzbd-keep-fixed-string-names"
      {
        mode = "keep";
        categories = trickyDeclared;
        getConfig = trickyLive;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ -z "$(deletes)" ] || fail "keep deleted: $(deletes)"
          expectLine out.txt 'nixflix: sabnzbd-categories: keeping 2 undeclared categories (nixflix.usenetClients.sabnzbd.syncMode.categories = "keep"): a.c, old'
        '';
      };

  # A declared "Movies" is live as "movies": nothing undeclared, refuse passes.
  sync-mode-dlclients-sabnzbd-refuse-case-insensitive =
    runSabnzbd "sync-mode-dlclients-sabnzbd-refuse-case-insensitive"
      {
        mode = "refuse";
        categories = [ "Movies" ];
        getConfig.config.categories = [
          {
            name = "*";
            order = 0;
          }
          {
            name = "movies";
            order = 1;
          }
        ];
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ -z "$(deletes)" ] || fail "deleted: $(deletes)"
          grep -q '^set_config&section=categories&.*name=Movies' calls.log || fail "sync did not proceed"
        '';
      };

  # --- qBittorrent -----------------------------------------------------------

  sync-mode-dlclients-qbittorrent-default-unchanged =
    let
      config = qbittorrentConfig { };
      preStart = config.systemd.services.qbittorrent.preStart;
      configPath = "${config.services.qbittorrent.profileDir}/qBittorrent/config";
    in
    assertTest "sync-mode-dlclients-qbittorrent-default-unchanged" (
      qbittorrentMode { } == "delete"
      && lib.hasInfix "cp -f '" preStart
      && lib.hasInfix "-categories.json' '${configPath}/categories.json'" preStart
      && !lib.hasInfix "nixflix-sync-guard" preStart
      && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" preStart
    );

  # syncMode is nixflix's own option: forwarding it into services.qbittorrent
  # would fail evaluation with "option does not exist".
  sync-mode-dlclients-qbittorrent-not-forwarded =
    let
      config = qbittorrentConfig { torrentClients.qbittorrent.syncMode.categories = "keep"; };
    in
    assertTest "sync-mode-dlclients-qbittorrent-not-forwarded" (
      config.services.qbittorrent.enable && !(config.services.qbittorrent ? syncMode)
    );

  sync-mode-dlclients-qbittorrent-refuse-guards =
    assertTest "sync-mode-dlclients-qbittorrent-refuse-guards"
      (
        guardPrecedesMutations qbRefuse
        && before "# nixflix-sync-guard" "cp -f" qbRefuse
        && before syncMode.refuseCheckpoint "cp -f" qbRefuse
        && before syncMode.refuseCheckpoint "chmod" qbRefuse
      );

  sync-mode-dlclients-qbittorrent-keep-merges =
    assertTest "sync-mode-dlclients-qbittorrent-keep-merges"
      (
        lib.hasInfix "'. * $declared[0]'" qbKeep
        && !lib.hasInfix "nixflix-sync-guard" qbKeep
        && lib.hasInfix "keeping " qbKeep
      );

  sync-mode-dlclients-qbittorrent-override-beats-global =
    assertTest "sync-mode-dlclients-qbittorrent-override-beats-global"
      (
        qbittorrentMode { syncMode = "keep"; } == "keep"
        && qbittorrentMode { syncMode = "refuse"; } == "refuse"
        && guardPrecedesMutations (qbittorrentPreStart {
          syncMode = "refuse";
        })
        &&
          qbittorrentPreStart {
            syncMode = "keep";
            torrentClients.qbittorrent.syncMode.categories = "delete";
          } == qbittorrentPreStart { }
        &&
          qbittorrentPreStart {
            syncMode = "refuse";
            torrentClients.qbittorrent.syncMode.categories = "keep";
          } == qbKeep
      );

  sync-mode-dlclients-qbittorrent-delete-run =
    runQbittorrent "sync-mode-dlclients-qbittorrent-delete-run"
      {
        mode = "delete";
        existing = existingQb;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not replaced: $(result)"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-run =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-run"
      {
        mode = "keep";
        existing = existingQb;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '{"manual":{"save_path":"/data/torrent/manual"},"radarr":{"save_path":"/data/torrent/radarr"},"sonarr":{"save_path":"/data/torrent/sonarr"},"with space":{"save_path":"/x"}}' ] \
            || fail "bad merge: $(result)"
          expectLine out.txt 'nixflix: qbittorrent: keeping 2 undeclared categories (nixflix.torrentClients.qbittorrent.syncMode.categories = "keep"): manual, with space'
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-first-start =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-first-start"
      {
        mode = "keep";
        existing = null;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-invalid-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-invalid-file"
      {
        mode = "keep";
        existing = "not json {";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not replaced: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-run =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-run"
      {
        mode = "refuse";
        existing = existingQb;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          cmp -s before.json config/categories.json || fail "refuse wrote categories.json"
          expectLine err.txt 'nixflix: qbittorrent: refusing to sync: 2 categories exist that are not declared (nixflix.torrentClients.qbittorrent.syncMode.categories = "refuse"). Nothing was changed.'
          expectLine err.txt 'nixflix:   - manual (id /data/torrent/manual)'
          expectLine err.txt 'nixflix:   - with space (id /x)'
          ! grep -q 'nixflix:   - radarr' err.txt || fail "declared category listed"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-all-declared =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-all-declared"
      {
        mode = "refuse";
        existing = ''{"radarr":{"save_path":"/old"}}'';
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-first-start =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-first-start"
      {
        mode = "refuse";
        existing = null;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
        '';
      };

  # qBittorrent loads nothing from a file that is not one JSON object, so
  # there is nothing undeclared: refuse writes the declared categories.
  sync-mode-dlclients-qbittorrent-refuse-invalid-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-invalid-file"
      {
        mode = "refuse";
        existing = "[1, 2]";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
          ! grep -q refusing err.txt || fail "refused"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-whitespace-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-whitespace-file"
      {
        mode = "keep";
        existing = " \n\t \n";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          ! grep -q 'not a JSON object' err.txt || fail "warned about a file with no categories"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-empty-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-empty-file"
      {
        mode = "keep";
        existing = "";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          ! grep -q 'not a JSON object' err.txt || fail "warned about a file with no categories"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-broken-json-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-broken-json-file"
      {
        mode = "keep";
        existing = "{ not json";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-keep-two-values-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-keep-two-values-file"
      {
        mode = "keep";
        existing = "{} {}";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-whitespace-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-whitespace-file"
      {
        mode = "refuse";
        existing = " \n\t \n";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          ! grep -q 'not a JSON object' err.txt || fail "warned about a file with no categories"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-empty-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-empty-file"
      {
        mode = "refuse";
        existing = "";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          ! grep -q 'not a JSON object' err.txt || fail "warned about a file with no categories"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-broken-json-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-broken-json-file"
      {
        mode = "refuse";
        existing = "{ not json";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };

  sync-mode-dlclients-qbittorrent-refuse-two-values-file =
    runQbittorrent "sync-mode-dlclients-qbittorrent-refuse-two-values-file"
      {
        mode = "refuse";
        existing = "{} {}";
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          [ "$(result)" = '${declaredQb}' ] || fail "not written: $(result)"
          grep -q 'categories.json is not a JSON object' err.txt || fail "no warning"
          ! grep -q -e refusing -e keeping out.txt err.txt || fail "listed categories that do not exist"
          [ "$(stat -c %a config/categories.json)" = 640 ] || fail "mode not 640"
        '';
      };
}
