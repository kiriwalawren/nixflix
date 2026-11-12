# nixflix.syncMode for the *arr root folder, delay profile, download client
# and notification sync units (modules/arr-common, modules/downloadarr,
# modules/notif).
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

  arrs = [
    "radarr"
    "sonarr"
    "sonarr-anime"
    "lidarr"
  ];

  # Every unit this file covers, with the collection it prunes and the text
  # of its (unchanged) delete loop.
  units =
    lib.concatMap (svc: [
      {
        unit = "${svc}-rootfolders";
        removing = "Removing root folders not in configuration...";
        deleteUrl = "/rootfolder/$FOLDER_ID";
      }
      {
        unit = "${svc}-delayprofiles";
        removing = "Removing delay profiles not in configuration...";
        deleteUrl = "/delayprofile/$PROFILE_ID";
      }
      {
        unit = "${svc}-notifications";
        removing = "Removing notifications not in configuration...";
        deleteUrl = "/notification/$NOTIFICATION_ID";
      }
    ]) arrs
    ++ map (svc: {
      unit = "${svc}-downloadclients";
      removing = "Removing download clients not in configuration...";
      deleteUrl = "/downloadclient/$CLIENT_ID";
    }) (arrs ++ [ "prowlarr" ]);

  # Notif's per-service blocks (#415): the connection is set up on every *arr.
  allArrBlocks = lib.genAttrs arrs (_: {
    enable = true;
  });

  arrConfig = svc: port: {
    enable = true;
    config = {
      hostConfig.port = port;
      apiKey._secret = "/run/secrets/${svc}-api";
      hostConfig.password._secret = "/run/secrets/${svc}-pw";
    };
  };

  baseNixflix = {
    enable = true;
    prowlarr = arrConfig "prowlarr" 9696;
    radarr = lib.recursiveUpdate (arrConfig "radarr" 7878) {
      config.rootFolders = [ { path = "/media/movies"; } ];
    };
    sonarr = lib.recursiveUpdate (arrConfig "sonarr" 8989) {
      config.rootFolders = [ { path = "/media/tv"; } ];
    };
    sonarr-anime = lib.recursiveUpdate (arrConfig "sonarr-anime" 8990) {
      config.rootFolders = [ { path = "/media/anime"; } ];
    };
    lidarr = lib.recursiveUpdate (arrConfig "lidarr" 8686) {
      config.rootFolders = [
        {
          path = "/media/music";
          name = "Music";
          defaultQualityProfileId = 1;
          defaultMetadataProfileId = 1;
        }
      ];
    };
    downloadarr.extraClients = [
      {
        enable = true;
        name = "SAB";
        implementationName = "SABnzbd";
        host = "localhost";
        port = 8080;
        apiKey = "sab-test-key";
        dependencies = [ ];
        categories = {
          radarr = "radarr";
          sonarr = "sonarr";
          sonarr-anime = "sonarr-anime";
          lidarr = "lidarr";
          prowlarr = "prowlarr";
        };
      }
    ];
    notif.extraNotifications = [
      (
        {
          name = "Ntfy";
          implementationName = "ntfy.sh";
          dependencies = [ ];
        }
        // allArrBlocks
      )
    ];
  };

  eval = extra: (evalConfig [ { nixflix = lib.recursiveUpdate baseNixflix extra; } ]).config;

  scriptsOf = cfg: lib.genAttrs (map (u: u.unit) units) (u: cfg.systemd.services.${u}.script);

  defaultCfg = eval { };
  defaultScripts = scriptsOf defaultCfg;
  explicitDeleteScripts = scriptsOf (eval {
    syncMode = "delete";
  });
  refuseScripts = scriptsOf (eval {
    syncMode = "refuse";
  });
  keepScripts = scriptsOf (eval {
    syncMode = "keep";
  });

  allUnits = pred: lib.all pred units;

  # Text before the refuse checkpoint, i.e. everything a refused run executes.
  beforeCheckpoint = script: builtins.head (lib.splitString syncMode.refuseCheckpoint script);

  hasDelete = script: lib.hasInfix "-X DELETE" script;

  # Replaces curl in a unit script with a fake that serves fixtures from
  # $FIXTURES/<endpoint>.json (slashes become _) and logs every mutating call
  # to $MUTATED_LOG as "<METHOD> <endpoint>", plus its `--data-binary @file`
  # body to $BODY_LOG.
  fakeCurl = pkgs.writeShellScript "fake-curl" ''
    method=GET
    url=
    data=
    while [ $# -gt 0 ]; do
      case "$1" in
        -X) method=$2; shift 2 ;;
        --data-binary) data=$2; shift 2 ;;
        --variable|--expand-header|--header|-d) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
      esac
    done
    endpoint=''${url#*/api/v*/}
    if [ "$method" = GET ]; then
      cat "$FIXTURES/$(printf '%s' "$endpoint" | tr / _).json"
    else
      echo "$method $endpoint" >> "$MUTATED_LOG"
      case "$data" in
        @*) { echo "$method $endpoint"; cat "''${data#@}"; } >> "$BODY_LOG" ;;
      esac
      echo '{}'
    fi
  '';

  runUnit =
    name:
    {
      script,
      fixtures,
      checks,
    }:
    let
      fixtureDir = pkgs.linkFarm "${name}-fixtures" (
        lib.mapAttrsToList (endpoint: value: {
          name = "${builtins.replaceStrings [ "/" ] [ "_" ] endpoint}.json";
          path = pkgs.writeText "fixture.json" (builtins.toJSON value);
        }) fixtures
      );
      scriptFile = pkgs.writeText "${name}.sh" (
        builtins.replaceStrings [ "${pkgs.curl}/bin/curl" ] [ "${fakeCurl}" ] script
      );
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      export FIXTURES=${fixtureDir} MUTATED_LOG=$PWD/mutated.log BODY_LOG=$PWD/bodies.log
      touch mutated.log bodies.log
      rc=0
      ${pkgs.bash}/bin/bash ${scriptFile} > out.txt 2> err.txt || rc=$?
      echo "rc=$rc"; echo "--- stdout"; cat out.txt; echo "--- stderr"; cat err.txt; echo "--- mutations"; cat mutated.log

      fail() { echo "FAIL: ${name}: $*"; exit 1; }
      expectLine() { grep -qFx -- "$2" "$1" || fail "missing line in $1: $2"; }
      ${checks}
      echo 'PASS: ${name}' > $out
    '';

  # Live state with one declared and one undeclared object per collection.
  rootFolderFixtures = {
    rootfolder = [
      {
        id = 1;
        path = "/media/movies";
      }
      {
        id = 5;
        path = "/srv/injected";
      }
    ];
  };

  delayProfileFixtures = {
    delayprofile = [
      {
        id = 1;
        order = 2147483647;
        tags = [ ];
      }
      {
        id = 4;
        order = 1;
        tags = [ 7 ];
      }
    ];
  };

  downloadClientFixtures = {
    "downloadclient/schema" = [
      {
        implementationName = "SABnzbd";
        fields = [ ];
      }
    ];
    downloadclient = [
      {
        id = 1;
        name = "SAB";
        implementationName = "SABnzbd";
        fields = [ ];
      }
      {
        id = 2;
        name = "Injected Client";
        implementationName = "SABnzbd";
        fields = [
          {
            name = "apiKey";
            value = "LIVE-SECRET";
          }
        ];
      }
    ];
  };

  notificationFixtures = {
    "notification/schema" = [
      {
        implementationName = "ntfy.sh";
        fields = [ ];
      }
    ];
    notification = [
      {
        id = 1;
        name = "Ntfy";
        implementationName = "ntfy.sh";
        fields = [ ];
      }
      {
        id = 3;
        name = "Injected Hook";
        implementationName = "Webhook";
        fields = [
          {
            name = "url";
            value = "https://LIVE-SECRET.example/hook";
          }
        ];
      }
    ];
  };

  scenarios = [
    {
      area = "rootfolders";
      unit = "radarr-rootfolders";
      fixtures = rootFolderFixtures;
      deleteCall = "DELETE rootfolder/5";
      declaredCall = null; # /media/movies already exists, so nothing is posted
      refuseLines = [
        ''nixflix: radarr-rootfolders: refusing to sync: 1 root folders exist that are not declared (nixflix.radarr.syncMode.rootFolders = "refuse"). Nothing was changed.''
        "nixflix:   - /srv/injected (id 5)"
      ];
      keepLine = ''nixflix: radarr-rootfolders: keeping 1 undeclared root folders (nixflix.radarr.syncMode.rootFolders = "keep"): /srv/injected'';
    }
    {
      area = "delayprofiles";
      unit = "sonarr-delayprofiles";
      fixtures = delayProfileFixtures;
      deleteCall = "DELETE delayprofile/4";
      declaredCall = "PUT delayprofile/1";
      refuseLines = [
        ''nixflix: sonarr-delayprofiles: refusing to sync: 1 delay profiles exist that are not declared (nixflix.sonarr.syncMode.delayProfiles = "refuse"). Nothing was changed.''
        "nixflix:   - 4 (id 4)"
      ];
      keepLine = ''nixflix: sonarr-delayprofiles: keeping 1 undeclared delay profiles (nixflix.sonarr.syncMode.delayProfiles = "keep"): 4'';
    }
    {
      area = "downloadclients";
      unit = "prowlarr-downloadclients";
      fixtures = downloadClientFixtures;
      deleteCall = "DELETE downloadclient/2";
      declaredCall = "PUT downloadclient/1";
      refuseLines = [
        ''nixflix: prowlarr-downloadclients: refusing to sync: 1 download clients exist that are not declared (nixflix.prowlarr.syncMode.downloadClients = "refuse"). Nothing was changed.''
        "nixflix:   - Injected Client (id 2)"
      ];
      keepLine = ''nixflix: prowlarr-downloadclients: keeping 1 undeclared download clients (nixflix.prowlarr.syncMode.downloadClients = "keep"): Injected Client'';
    }
    {
      area = "notifications";
      unit = "radarr-notifications";
      fixtures = notificationFixtures;
      deleteCall = "DELETE notification/3";
      declaredCall = "PUT notification/1";
      refuseLines = [
        ''nixflix: radarr-notifications: refusing to sync: 1 notifications exist that are not declared (nixflix.radarr.syncMode.notifications = "refuse"). Nothing was changed.''
        "nixflix:   - Injected Hook (id 3)"
      ];
      keepLine = ''nixflix: radarr-notifications: keeping 1 undeclared notifications (nixflix.radarr.syncMode.notifications = "keep"): Injected Hook'';
    }
  ];

  expectDeclaredCall =
    s:
    lib.optionalString (s.declaredCall != null) ''
      grep -qFx ${lib.escapeShellArg s.declaredCall} mutated.log || fail "declared object not updated"
    '';

  noLeak = ''
    ! grep -q LIVE-SECRET out.txt err.txt || fail "live object contents leaked into the log"
  '';

  scenarioTests = lib.concatMap (
    s:
    let
      prefix = "sync-mode-arr-common-run-${s.area}";
    in
    [
      {
        name = "${prefix}-delete";
        value = runUnit "${prefix}-delete" {
          script = defaultScripts.${s.unit};
          inherit (s) fixtures;
          checks = ''
            [ "$rc" = 0 ] || fail "rc=$rc"
            grep -qFx ${lib.escapeShellArg s.deleteCall} mutated.log || fail "undeclared object not deleted"
            ${expectDeclaredCall s}
          '';
        };
      }
      {
        name = "${prefix}-keep";
        value = runUnit "${prefix}-keep" {
          script = keepScripts.${s.unit};
          inherit (s) fixtures;
          checks = ''
            [ "$rc" = 0 ] || fail "rc=$rc"
            ! grep -q '^DELETE' mutated.log || fail "keep deleted something"
            ${expectDeclaredCall s}
            expectLine out.txt ${lib.escapeShellArg s.keepLine}
            ${noLeak}
          '';
        };
      }
      {
        name = "${prefix}-refuse";
        value = runUnit "${prefix}-refuse" {
          script = refuseScripts.${s.unit};
          inherit (s) fixtures;
          checks = ''
            [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
            [ ! -s mutated.log ] || fail "refuse mutated the service"
            ${lib.concatMapStringsSep "\n" (l: "expectLine err.txt ${lib.escapeShellArg l}") s.refuseLines}
            ${noLeak}
          '';
        };
      }
    ]
  ) scenarios;

  # #414 lets any notification field be a `_secret` file. keep must still write
  # the declared notification with the secret resolved, refuse must stop
  # before it is read or sent, and neither may print it.
  ntfySecret = pkgs.writeText "ntfy-server-url" "https://NTFY-SECRET.example";
  secretNotificationScripts =
    mode:
    scriptsOf (eval {
      syncMode = mode;
      notif.extraNotifications = [
        (
          {
            name = "Ntfy";
            implementationName = "ntfy.sh";
            dependencies = [ ];
            serverUrl._secret = ntfySecret;
          }
          // allArrBlocks
        )
      ];
    });
  secretNotificationFixtures = notificationFixtures // {
    notification = map (
      n:
      if n.id == 1 then
        n
        // {
          fields = [
            {
              name = "serverUrl";
              value = "";
            }
          ];
        }
      else
        n
    ) notificationFixtures.notification;
  };
  noSecretInLog = ''
    ! grep -q NTFY-SECRET out.txt err.txt || fail "declared secret leaked into the log"
  '';

  # #419: the typed ntfy connector's topics can be `_secret` files.
  ntfyTopicSecret = pkgs.writeText "ntfy-topic" "NTFY-TOPIC-SECRET";
  ntfyTopicScripts =
    mode:
    scriptsOf (eval {
      syncMode = mode;
      notif = {
        extraNotifications = [ ];
        ntfy = {
          name = "Ntfy";
          topics = [ { _secret = ntfyTopicSecret; } ];
          radarr.enable = true;
        };
      };
    });
  ntfyTopicFixtures = notificationFixtures // {
    notification = map (
      n:
      if n.id == 1 then
        n
        // {
          fields = [
            {
              name = "topics";
              value = [ ];
            }
          ];
        }
      else
        n
    ) notificationFixtures.notification;
  };
  noTopicSecretInLog = ''
    ! grep -q NTFY-TOPIC-SECRET out.txt err.txt || fail "ntfy topic secret leaked into the log"
  '';

  # Live delay profiles holding only the built-in id 1 must never block refuse.
  delayProfileBuiltinOnly = {
    delayprofile = [
      {
        id = 1;
        order = 2147483647;
        tags = [ ];
      }
    ];
  };
in
lib.listToAttrs scenarioTests
// {
  sync-mode-arr-common-default-unchanged = assertTest "sync-mode-arr-common-default-unchanged" (
    allUnits (
      u:
      let
        s = defaultScripts.${u.unit};
      in
      lib.hasInfix u.removing s
      && lib.hasInfix "-X DELETE" s
      && lib.hasInfix u.deleteUrl s
      && !lib.hasInfix "# nixflix-sync-guard" s
      && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" s
      && !lib.hasInfix "keeping" s
      && explicitDeleteScripts.${u.unit} == s
    )
  );

  sync-mode-arr-common-option-defaults = assertTest "sync-mode-arr-common-option-defaults" (
    let
      n = defaultCfg.nixflix;
      k = (eval { syncMode = "keep"; }).nixflix;
    in
    lib.all (
      svc:
      n.${svc}.syncMode.rootFolders == "delete"
      && n.${svc}.syncMode.delayProfiles == "delete"
      && n.${svc}.syncMode.downloadClients == "delete"
      && n.${svc}.syncMode.notifications == "delete"
      && k.${svc}.syncMode.rootFolders == "keep"
      && k.${svc}.syncMode.delayProfiles == "keep"
      && k.${svc}.syncMode.downloadClients == "keep"
      && k.${svc}.syncMode.notifications == "keep"
    ) arrs
    && n.prowlarr.syncMode.downloadClients == "delete"
    && k.prowlarr.syncMode.downloadClients == "keep"
    && !(n.prowlarr.syncMode ? rootFolders)
    && !(n.prowlarr.syncMode ? delayProfiles)
    && !(n.prowlarr.syncMode ? notifications)
  );

  # The overrides live on the *arr side: downloadarr and notif turn every
  # attribute of theirs into a client/notification.
  sync-mode-arr-common-no-passthrough-leak = assertTest "sync-mode-arr-common-no-passthrough-leak" (
    let
      cfg = eval { syncMode = "refuse"; };
    in
    !(cfg.nixflix.downloadarr ? syncMode)
    && !(cfg.nixflix.notif ? syncMode)
    && lib.all (
      svc: lib.hasInfix ''--argjson declared '["SAB"]' '' refuseScripts."${svc}-downloadclients"
    ) (arrs ++ [ "prowlarr" ])
    && lib.all (
      svc: lib.hasInfix ''--argjson declared '["Ntfy"]' '' refuseScripts."${svc}-notifications"
    ) arrs
  );

  sync-mode-arr-common-refuse-guards = assertTest "sync-mode-arr-common-refuse-guards" (
    allUnits (
      u:
      let
        s = refuseScripts.${u.unit};
      in
      guardPrecedesMutations s
      && lib.hasInfix "# nixflix-sync-guard: ${u.unit} " s
      && lib.hasInfix syncMode.refuseCheckpoint s
      && !hasDelete s
      && !lib.hasInfix u.removing s
      && !lib.hasInfix "-X POST" (beforeCheckpoint s)
      && !lib.hasInfix "-X PUT" (beforeCheckpoint s)
    )
  );

  sync-mode-arr-common-keep-no-delete = assertTest "sync-mode-arr-common-keep-no-delete" (
    allUnits (
      u:
      let
        s = keepScripts.${u.unit};
      in
      !hasDelete s
      && !lib.hasInfix u.removing s
      && lib.hasInfix ": keeping " s
      && !lib.hasInfix "# nixflix-sync-guard" s
      && !lib.hasInfix "NIXFLIX_SYNC_REFUSED" s
    )
  );

  sync-mode-arr-common-override-beats-global =
    let
      refuseButDelete = scriptsOf (eval {
        syncMode = "refuse";
        radarr.syncMode.rootFolders = "delete";
        prowlarr.syncMode.downloadClients = "keep";
      });
      deleteButRefuse = scriptsOf (eval {
        sonarr.syncMode.delayProfiles = "refuse";
        lidarr.syncMode.notifications = "keep";
      });
    in
    assertTest "sync-mode-arr-common-override-beats-global" (
      refuseButDelete.radarr-rootfolders == defaultScripts.radarr-rootfolders
      && refuseButDelete.prowlarr-downloadclients == keepScripts.prowlarr-downloadclients
      && refuseButDelete.radarr-delayprofiles == refuseScripts.radarr-delayprofiles
      && refuseButDelete.sonarr-rootfolders == refuseScripts.sonarr-rootfolders
      && deleteButRefuse.sonarr-delayprofiles == refuseScripts.sonarr-delayprofiles
      && deleteButRefuse.lidarr-notifications == keepScripts.lidarr-notifications
      && deleteButRefuse.sonarr-rootfolders == defaultScripts.sonarr-rootfolders
      && deleteButRefuse.sonarr-anime-delayprofiles == defaultScripts.sonarr-anime-delayprofiles
    );

  sync-mode-arr-common-run-delayprofiles-refuse-builtin-only =
    runUnit "sync-mode-arr-common-run-delayprofiles-refuse-builtin-only"
      {
        script = refuseScripts.sonarr-delayprofiles;
        fixtures = delayProfileBuiltinOnly;
        checks = ''
          [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
          grep -qFx 'PUT delayprofile/1' mutated.log || fail "default profile not updated"
          [ ! -s err.txt ] || fail "unexpected stderr"
        '';
      };

  sync-mode-arr-common-run-rootfolders-refuse-all-declared =
    runUnit "sync-mode-arr-common-run-rootfolders-refuse-all-declared"
      {
        script = refuseScripts.radarr-rootfolders;
        fixtures.rootfolder = [ ];
        checks = ''
          [ "$rc" = 0 ] || fail "expected rc 0, got $rc"
          grep -qFx 'POST rootfolder' mutated.log || fail "declared root folder not created"
        '';
      };

  sync-mode-arr-common-run-downloadclients-refuse-failed-get =
    runUnit "sync-mode-arr-common-run-downloadclients-refuse-failed-get"
      {
        script = refuseScripts.radarr-downloadclients;
        fixtures = downloadClientFixtures // {
          downloadclient = {
            message = "Unauthorized";
          };
        };
        checks = ''
          [ "$rc" = 1 ] || fail "expected rc 1, got $rc"
          [ ! -s mutated.log ] || fail "mutated after a failed GET"
          grep -q 'nixflix: radarr-downloadclients: cannot check for undeclared download clients' err.txt || fail "no error message"
        '';
      };

  sync-mode-arr-common-run-notifications-secret-keep =
    runUnit "sync-mode-arr-common-run-notifications-secret-keep"
      {
        script = (secretNotificationScripts "keep").radarr-notifications;
        fixtures = secretNotificationFixtures;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          ! grep -q '^DELETE' mutated.log || fail "keep deleted something"
          grep -qFx 'PUT notification/1' mutated.log || fail "declared notification not updated"
          sed -n '/^PUT notification\/1$/,$p' bodies.log | tail -n +2 \
            | ${pkgs.jq}/bin/jq -e '.fields[] | select(.name == "serverUrl") | .value == "https://NTFY-SECRET.example"' >/dev/null \
            || fail "secret field not resolved into the PUT body"
          expectLine out.txt 'nixflix: radarr-notifications: keeping 1 undeclared notifications (nixflix.radarr.syncMode.notifications = "keep"): Injected Hook'
          ${noLeak}
          ${noSecretInLog}
        '';
      };

  sync-mode-arr-common-run-notifications-secret-refuse =
    runUnit "sync-mode-arr-common-run-notifications-secret-refuse"
      {
        script = (secretNotificationScripts "refuse").radarr-notifications;
        fixtures = secretNotificationFixtures;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          [ ! -s mutated.log ] || fail "refuse mutated the service"
          [ ! -s bodies.log ] || fail "refuse sent a body"
          expectLine err.txt 'nixflix:   - Injected Hook (id 3)'
          ${noLeak}
          ${noSecretInLog}
        '';
      };

  sync-mode-arr-common-run-notifications-ntfy-topic-secret-keep =
    runUnit "sync-mode-arr-common-run-notifications-ntfy-topic-secret-keep"
      {
        script = (ntfyTopicScripts "keep").radarr-notifications;
        fixtures = ntfyTopicFixtures;
        checks = ''
          [ "$rc" = 0 ] || fail "rc=$rc"
          ! grep -q '^DELETE' mutated.log || fail "keep deleted something"
          grep -qFx 'PUT notification/1' mutated.log || fail "declared notification not updated"
          sed -n '/^PUT notification\/1$/,$p' bodies.log | tail -n +2 \
            | ${pkgs.jq}/bin/jq -e '.fields[] | select(.name == "topics") | .value | tostring | contains("NTFY-TOPIC-SECRET")' >/dev/null \
            || fail "topic secret not resolved into the PUT body"
          expectLine out.txt 'nixflix: radarr-notifications: keeping 1 undeclared notifications (nixflix.radarr.syncMode.notifications = "keep"): Injected Hook'
          ${noLeak}
          ${noTopicSecretInLog}
        '';
      };

  sync-mode-arr-common-run-notifications-ntfy-topic-secret-refuse =
    runUnit "sync-mode-arr-common-run-notifications-ntfy-topic-secret-refuse"
      {
        script = (ntfyTopicScripts "refuse").radarr-notifications;
        fixtures = ntfyTopicFixtures;
        checks = ''
          [ "$rc" = 78 ] || fail "expected rc 78, got $rc"
          [ ! -s mutated.log ] || fail "refuse mutated the service"
          expectLine err.txt 'nixflix:   - Injected Hook (id 3)'
          ${noLeak}
          ${noTopicSecretInLog}
        '';
      };
}
