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

  fakePlugin = pkgs.runCommand "fake-plugin-1.0.0.0" { } ''
    mkdir -p "$out"
    echo dll > "$out/Fake.dll"
  '';

  arrConfig = svc: port: rootFolder: {
    enable = true;
    config = {
      hostConfig.port = port;
      apiKey._secret = "/run/secrets/${svc}-api";
      hostConfig.password._secret = "/run/secrets/${svc}-pw";
      rootFolders = [ { path = rootFolder; } ];
    };
  };

  sabCategory = name: {
    inherit name;
    dir = name;
    priority = 0;
    pp = 3;
    script = "None";
  };

  # Every collection nixflix can prune, enabled at once. The *arrs also add
  # their own Jellyfin libraries, so `libraries` ends up with more than Movies.
  everything = {
    # sabnzbd.service's ExecStart is read too, and SABnzbd pulls in unrar.
    nixpkgs.config.allowUnfreePredicate = p: lib.getName p == "unrar";

    nixflix = {
      enable = true;
      radarr = arrConfig "radarr" 7878 "/media/movies";
      sonarr = arrConfig "sonarr" 8989 "/media/tv";
      sonarr-anime = arrConfig "sonarr-anime" 8990 "/media/anime";
      lidarr = lib.recursiveUpdate (arrConfig "lidarr" 8686 "/media/music") {
        config.rootFolders = [
          {
            path = "/media/music";
            name = "Music";
            defaultQualityProfileId = 1;
            defaultMetadataProfileId = 1;
          }
        ];
      };
      prowlarr = {
        enable = true;
        config = {
          hostConfig.port = 9696;
          apiKey._secret = "/run/secrets/prowlarr-api";
          hostConfig.password._secret = "/run/secrets/prowlarr-pw";
          indexers = [ { name = "Declared Indexer"; } ];
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
        {
          enable = true;
          name = "Ntfy";
          implementationName = "ntfy.sh";
          services = [
            "radarr"
            "sonarr"
            "sonarr-anime"
            "lidarr"
          ];
          dependencies = [ ];
        }
      ];
      seerr = {
        enable = true;
        apiKey._secret = "/run/secrets/seerr-api";
        jellyfin = {
          adminUsername = "admin";
          adminPassword = "password";
          # With every library enabled there is nothing to switch off, so the
          # jellyfinLibraries guard only exists on the filter path.
          enableAllLibraries = false;
          libraryFilter.types = [ "movie" ];
        };
        radarr.Main.apiKey._secret = "/run/secrets/radarr";
        sonarr.Main.apiKey._secret = "/run/secrets/sonarr";
      };
      jellyfin = {
        enable = true;
        apiKey = "test-jellyfin-key";
        users.admin = {
          password = "testpassword";
          policy.isAdministrator = true;
        };
        libraries.Movies = {
          collectionType = "movies";
          paths = [ "/srv/movies" ];
        };
        plugins."Fake Plugin" = {
          enable = true;
          package = fakePlugin;
        };
        liveTv = {
          tuners.a = {
            url = "/srv/a.m3u";
            friendlyName = "Tuner A";
          };
          listingProviders.guide = {
            path = "/srv/guide.xml";
            tuners = [ "a" ];
          };
        };
      };
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
      usenetClients.sabnzbd = {
        enable = true;
        settings = {
          misc = {
            api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey";
            nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey";
          };
          categories = [ (sabCategory "radarr") ];
        };
      };
      torrentClients.qbittorrent = {
        enable = true;
        password._secret = pkgs.writeText "qbittorrent-password" "pw";
        categories.radarr = "/data/torrent/radarr";
      };
      recyclarr = {
        enable = true;
        cleanupUnmanagedProfiles = {
          enable = true;
          managedProfiles = [ "Managed" ];
        };
      };
    };
  };

  evalWith =
    global:
    evalConfig [
      everything
      (lib.optionalAttrs (global != null) { nixflix.syncMode = global; })
    ];

  # Store-path context makes lib.hasInfix reject a string; the text is all we need.
  plain = builtins.unsafeDiscardStringContext;

  textOf =
    v:
    if builtins.isList v then
      lib.concatMapStringsSep "\n" textOf v
    else if lib.isDerivation v && v ? text then
      v.text
    else if builtins.isString v then
      v
    else
      "";

  # Everything a unit runs that nixflix generates: script, preStart (qBittorrent
  # syncs categories there) and writeShellApplication ExecStarts (maintainerr,
  # recyclarr). seerr-libraries `source`s a separate script, read separately.
  unitText =
    evaluated: name:
    let
      s = evaluated.config.systemd.services.${name};
      sc = s.serviceConfig or { };
    in
    plain (
      lib.concatMapStringsSep "\n" textOf [
        (s.preStart or "")
        (s.script or "")
        (s.postStart or "")
        (sc.ExecStartPre or "")
        (sc.ExecStart or "")
        (sc.ExecStartPost or "")
      ]
    );

  seerrLibrarySyncText =
    evaluated:
    let
      cfg = evaluated.config.nixflix.seerr;
      authUtil = import ../../modules/seerr/authUtil.nix {
        inherit lib cfg;
        inherit (evaluated) pkgs;
      };
    in
    plain
      (import ../../modules/seerr/librarySync.nix {
        inherit lib cfg;
        inherit (evaluated) pkgs;
      } authUtil.curlAuthArgs).text;

  render =
    global:
    let
      evaluated = evalWith global;
      inherit (evaluated) config;
      names = builtins.attrNames config.systemd.services;
    in
    {
      inherit config;
      texts = lib.genAttrs names (unitText evaluated) // {
        seerr-libraries = unitText evaluated "seerr-libraries" + "\n" + seerrLibrarySyncText evaluated;
      };
    };

  defaults = render null;
  explicitDelete = render "delete";
  keep = render "keep";
  refuse = render "refuse";
  explicitCfRefuse = {
    inherit
      (evalConfig [
        everything
        {
          nixflix.syncMode = "refuse";
          nixflix.recyclarr.syncMode.customFormats = "refuse";
        }
      ])
      config
      ;
  };

  # Every per-collection option, relative to `nixflix` (the table in
  # docs/examples/adopting-existing-install.md).
  collectionOptions =
    lib.concatMap
      (svc: [
        "${svc}.syncMode.rootFolders"
        "${svc}.syncMode.delayProfiles"
        "${svc}.syncMode.downloadClients"
        "${svc}.syncMode.notifications"
      ])
      [
        "radarr"
        "sonarr"
        "sonarr-anime"
        "lidarr"
      ]
    ++ [
      "prowlarr.syncMode.downloadClients"
      "prowlarr.syncMode.indexers"
      "prowlarr.syncMode.indexerProxies"
      "prowlarr.syncMode.applications"
      "lidarr.syncMode.qualityProfiles"
      "lidarr.syncMode.metadataProfiles"
      "seerr.syncMode.radarr"
      "seerr.syncMode.sonarr"
      "seerr.syncMode.jellyfinLibraries"
      "jellyfin.syncMode.libraries"
      "jellyfin.syncMode.libraryPaths"
      "jellyfin.syncMode.plugins"
      "jellyfin.syncMode.liveTv"
      "maintainerr.syncMode.radarr"
      "maintainerr.syncMode.sonarr"
      "maintainerr.syncMode.rules"
      "maintainerr.syncMode.overlayTemplates"
      "usenetClients.sabnzbd.syncMode.categories"
      "torrentClients.qbittorrent.syncMode.categories"
      "recyclarr.syncMode.qualityProfiles"
      "recyclarr.syncMode.customFormats"
    ];

  # Recyclarr cannot enforce "refuse" for custom formats, so a global
  # "refuse" gives "keep" there; everything else follows the global.
  expectedMode =
    r: path:
    if path == "recyclarr.syncMode.customFormats" && r.config.nixflix.syncMode == "refuse" then
      "keep"
    else
      r.config.nixflix.syncMode;

  modeOf = r: path: lib.attrByPath (lib.splitString "." path) "<missing option>" r.config.nixflix;
  allModesAre = r: mode: lib.all (p: modeOf r p == mode) collectionOptions;

  arrs = [
    "radarr"
    "sonarr"
    "sonarr-anime"
    "lidarr"
  ];

  # Every unit that prunes undeclared objects. Under "refuse" each must carry a
  # guard; under "delete" each must still contain its delete loop.
  pruningUnits =
    lib.concatMap (svc: [
      "${svc}-rootfolders"
      "${svc}-delayprofiles"
      "${svc}-downloadclients"
      "${svc}-notifications"
    ]) arrs
    ++ [
      "lidarr-qualityprofiles"
      "lidarr-metadataprofiles"
      "prowlarr-downloadclients"
      "prowlarr-indexers"
      "prowlarr-indexer-proxies"
      "prowlarr-applications"
      "seerr-radarr"
      "seerr-sonarr"
      "seerr-libraries"
      "jellyfin-libraries"
      "jellyfin-plugins"
      "jellyfin-livetv"
      "maintainerr-settings"
      "maintainerr-rules"
      "maintainerr-overlay-templates"
      "sabnzbd-categories"
      "qbittorrent"
      "recyclarr-cleanup-profiles"
    ];

  count = needle: text: builtins.length (lib.splitString needle text) - 1;
  beforeCheckpoint = text: builtins.head (lib.splitString syncMode.refuseCheckpoint text);
  beforeGuard = text: builtins.head (lib.splitString "# nixflix-sync-guard" text);

  # What removing an object looks like in a generated script: HTTP DELETEs
  # (raw curl and the jellyfin-livetv `api` helper), SABnzbd's del_config,
  # managed directory removal, the qBittorrent categories.json overwrite, and
  # the delete loops that have no unique verb (jellyfin libraries/paths,
  # managed plugin dirs, Seerr switching undeclared libraries off).
  deletions = [
    "-X DELETE"
    "api DELETE"
    "del_config"
    "rm -rf"
    "cp -f"
    "Deleting removed library"
    "Removing path:"
    "Removed managed plugin directory"
    ''"\($id) \($enabled | index($id) != null)"''
  ];

  # THE allowlist: every deletion that may remain under "keep" or "refuse".
  # Each entry is named, says why it only touches declared objects, and pins
  # the exact count for the mode it applies to; any (unit, pattern) not listed
  # must occur zero times.
  #
  # Not visible here, so documented instead (docs/examples/adopting-existing-install.md):
  # the sabnzbd unit rewrites sabnzbd.ini from the template on every start
  # (settings added in the UI are dropped in every mode), outside any sync unit.
  exemptions =
    r:
    let
      packagedPlugins = builtins.length (
        builtins.attrNames (
          lib.filterAttrs (_: p: p.enable && p.package != null) r.config.nixflix.jellyfin.plugins
        )
      );
    in
    {
      # The superseded-version removal of DECLARED plugins (one loop) plus
      # wiping each declared packaged plugin's own directory before copying
      # it in again. Undeclared managed directories go through the guard.
      plugin-reinstall = {
        unit = "jellyfin-plugins";
        pattern = "rm -rf";
        count = 1 + packagedPlugins;
      };
      # refuse overwrites categories.json with the declared categories only
      # after its checkpoint, i.e. once every live category is declared.
      # keep merges with jq instead and has no `cp -f`.
      qbittorrent-refuse-write = {
        unit = "qbittorrent";
        pattern = "cp -f";
        count = if r.config.nixflix.syncMode == "refuse" then 1 else 0;
      };
    };

  allowedCount =
    r: unit: pattern:
    let
      hits = lib.filter (e: e.unit == unit && e.pattern == pattern) (builtins.attrValues (exemptions r));
    in
    if hits == [ ] then 0 else (builtins.head hits).count;

  unexpectedDeletions =
    r:
    lib.concatLists (
      lib.mapAttrsToList (
        unit: text:
        lib.concatMap (
          p:
          let
            n = count p text;
            ok = allowedCount r unit p;
          in
          lib.optional (n != ok) "${unit}: ${toString n} x '${p}' (allowed ${toString ok})"
        ) deletions
      ) r.texts
    );

  # A declared library whose collectionType differs is deleted and recreated
  # by delete mode only; keep skips it and refuse refuses it.
  recreates = r: count "recreating library..." r.texts.jellyfin-libraries;
  skippedRecreates = r: count "not recreating library" r.texts.jellyfin-libraries;
  declaredLibraries = r: builtins.length (builtins.attrNames r.config.nixflix.jellyfin.libraries);

  # Calls that change state, which a refused run must not reach. SABnzbd's API
  # is GET-only: its mutations are the `mode=` values.
  mutations = [
    "-X POST"
    "-X PUT"
    "-X DELETE"
    "api POST"
    "api PUT"
    "api DELETE"
    "del_config"
    "set_config"
    "rm -rf"
    "cp -f"
    "systemctl stop"
  ];

  guarded =
    r:
    builtins.filter (u: lib.hasInfix "# nixflix-sync-guard" r.texts.${u}) (builtins.attrNames r.texts);

  # Generic refuse shape: guard before every mutation, exactly one checkpoint,
  # and nothing state-changing ahead of the checkpoint.
  refuseShape =
    text:
    guardPrecedesMutations text
    && count syncMode.refuseCheckpoint text == 1
    && lib.all (m: !lib.hasInfix m (beforeCheckpoint text)) mutations;

  # seerr-libraries can only read the library list through
  # `POST .../library/sync` (refreshes Seerr's copy, keeps the enabled flags),
  # so that one POST precedes the guard; no PUT (the only call that switches a
  # library on or off) does. Mirrors tests/unit-tests/sync-mode-seerr.nix.
  seerrLibrariesShape =
    text:
    let
      preGuard = beforeGuard text;
      early = beforeCheckpoint text;
    in
    lib.hasInfix "# nixflix-sync-guard" text
    && count "-X POST" preGuard == 1
    && lib.hasInfix "/api/v1/settings/jellyfin/library/sync" preGuard
    && count "-X POST" early == 1
    && count syncMode.refuseCheckpoint text == 1
    && lib.all (m: m == "-X POST" || !lib.hasInfix m early) mutations;

  refuseShapeOf = unit: if unit == "seerr-libraries" then seerrLibrariesShape else refuseShape;

  recyclarrInstances =
    r:
    lib.concatMap builtins.attrValues (
      builtins.attrValues (
        lib.filterAttrs (n: _: n == "radarr" || n == "sonarr") r.config.nixflix.recyclarr.config
      )
    );
  deletesOldCustomFormats = r: map (i: i.delete_old_custom_formats or null) (recyclarrInstances r);
  customFormatsWarning =
    r:
    lib.any (lib.hasInfix "syncMode.customFormats = \"refuse\" cannot be enforced") r.config.warnings;

  report = xs: if xs == [ ] then true else builtins.trace (lib.concatStringsSep "\n" xs) false;
in
{
  sync-mode-coverage-default-is-delete = assertTest "sync-mode-coverage-default-is-delete" (
    defaults.config.nixflix.syncMode == "delete" && allModesAre defaults "delete"
  );

  sync-mode-coverage-options-follow-global = assertTest "sync-mode-coverage-options-follow-global" (
    report (
      lib.concatMap
        (
          r:
          lib.concatMap (
            p:
            lib.optional (
              modeOf r p != expectedMode r p
            ) "nixflix.${p} = ${modeOf r p} under global ${r.config.nixflix.syncMode}"
          ) collectionOptions
        )
        [
          explicitDelete
          keep
          refuse
        ]
    )
  );

  # "delete" must stay byte-for-byte the historical behaviour: an explicit
  # global "delete" renders exactly what the default renders, with no guard.
  sync-mode-coverage-delete-unchanged = assertTest "sync-mode-coverage-delete-unchanged" (
    explicitDelete.texts == defaults.texts
    && guarded defaults == [ ]
    && lib.all (t: !lib.hasInfix "NIXFLIX_SYNC_REFUSED" t) (builtins.attrValues defaults.texts)
  );

  # Keeps the deletion list honest: under "delete" every pruning unit still
  # matches it, so a zero count under keep/refuse means something.
  sync-mode-coverage-delete-loops-detected = assertTest "sync-mode-coverage-delete-loops-detected" (
    report (
      map (u: "${u}: no deletion pattern under delete") (
        builtins.filter (u: !lib.any (p: lib.hasInfix p defaults.texts.${u}) deletions) pruningUnits
      )
    )
  );

  sync-mode-coverage-keep-deletes-nothing-undeclared =
    assertTest "sync-mode-coverage-keep-deletes-nothing-undeclared"
      (report (unexpectedDeletions keep) && guarded keep == [ ]);

  sync-mode-coverage-refuse-deletes-nothing-undeclared =
    assertTest "sync-mode-coverage-refuse-deletes-nothing-undeclared"
      (
        report (
          unexpectedDeletions refuse
          ++ lib.mapAttrsToList (name: _e: "${name}: allowlisted deletion before the refuse checkpoint") (
            lib.filterAttrs (_: e: lib.hasInfix e.pattern (beforeCheckpoint refuse.texts.${e.unit})) (
              exemptions refuse
            )
          )
        )
      );

  sync-mode-coverage-refuse-guards-every-unit =
    assertTest "sync-mode-coverage-refuse-guards-every-unit"
      (
        report (
          lib.optional (
            lib.sort lib.lessThan (guarded refuse) != lib.sort lib.lessThan pruningUnits
          ) "guarded units ${toString (guarded refuse)} != pruning units ${toString pruningUnits}"
          ++ map (u: "${u}: refuse shape violated") (
            builtins.filter (u: !refuseShapeOf u refuse.texts.${u}) pruningUnits
          )
        )
      );

  # Recyclarr deletes custom formats itself, so the mode only picks the default
  # of delete_old_custom_formats. A global "refuse" gives "keep" there without
  # a warning; only an explicit customFormats = "refuse" warns.
  sync-mode-coverage-recyclarr-custom-formats =
    assertTest "sync-mode-coverage-recyclarr-custom-formats"
      (
        builtins.length (recyclarrInstances defaults) == 3
        && lib.all (v: v == true) (deletesOldCustomFormats defaults)
        && lib.all (v: v == false) (deletesOldCustomFormats keep)
        && lib.all (v: v == false) (deletesOldCustomFormats refuse)
        && lib.all (v: v == false) (deletesOldCustomFormats explicitCfRefuse)
        && !customFormatsWarning defaults
        && !customFormatsWarning keep
        && !customFormatsWarning refuse
        && customFormatsWarning explicitCfRefuse
      );

  sync-mode-coverage-recreate-only-in-delete =
    assertTest "sync-mode-coverage-recreate-only-in-delete"
      (
        report (
          lib.optional (recreates defaults != declaredLibraries defaults)
            "delete: ${toString (recreates defaults)} recreate branches for ${toString (declaredLibraries defaults)} libraries"
          ++
            lib.concatMap
              (
                r:
                lib.optional (recreates r != 0 || skippedRecreates r != declaredLibraries r)
                  "${r.config.nixflix.syncMode}: ${toString (recreates r)} recreates, ${toString (skippedRecreates r)} skips"
              )
              [
                keep
                refuse
              ]
        )
      );
}
