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

  renderer = import ../lib/sync-mode-render.nix {
    inherit lib pkgs;
    src = ../..;
    evalModules = evalConfig;
  };
  inherit (renderer) render;
  everything = import ../lib/sync-mode-everything.nix { inherit pkgs lib; };
  withGlobal = global: render (lib.optional (global != null) { nixflix.syncMode = global; });

  defaults = withGlobal null;
  explicitDelete = withGlobal "delete";
  keep = withGlobal "keep";
  refuse = withGlobal "refuse";
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
      "maintainerr.syncMode.mediaServer"
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
  #
  # The bare "DELETE", "rm -r", "rmdir", "unlink" and " -delete" entries are the
  # catch-all for units written later: any HTTP helper (`--request DELETE`,
  # `foo_request DELETE`), SQL DELETE or recursive removal, so a new pruning
  # unit that skips lib/sync-mode.nix fails the keep/refuse tests below.
  deletions = [
    "-X DELETE"
    "api DELETE"
    "DELETE"
    "del_config"
    "rm -rf"
    "rm -r"
    "rmdir"
    "unlink"
    " -delete"
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
      # The same removals, seen by the "rm -r" catch-all.
      plugin-reinstall-rm-r = {
        unit = "jellyfin-plugins";
        pattern = "rm -r";
        count = 1 + packagedPlugins;
      };
      # Replaces the API key nixflix itself owns (Name='nixflix') in one
      # transaction; no other key is touched.
      jellyfin-own-api-key = {
        unit = "jellyfin-api-key";
        pattern = "DELETE";
        count = 1;
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

  goldens = lib.importJSON ../lib/sync-mode-delete-goldens.json;
  currentHashes = renderer.hashes defaults.texts;
  # The only delete-mode changes against upstream, each with its reason and
  # the hash it must have now (from the test's failure message).
  intentionalDeleteChanges = {
    sabnzbd-categories = {
      reason = "Delete-loop fix (CHANGELOG, Fixed): names are read one per line, URL-encoded, \"*\" is never deleted, and matching is fixed-string and ASCII case-insensitive.";
      hash = "8560eaf77e2796bd7b1fcb6a24164c1f151ca6e20dc3b39878899bb1e93fd94a";
    };
  };

  report = xs: if xs == [ ] then true else builtins.trace (lib.concatStringsSep "\n" xs) false;

  # Source-level backstop for modules `everything` does not enable: every
  # module file that can remove something must go through syncMode, or be
  # listed here with the reason it only touches what nixflix owns.
  modulesDir = ../../modules;
  sourceTokens = [
    "DELETE"
    "del_config"
    "rm -r"
    "rmdir"
    "unlink"
    " -delete"
  ];
  sourceExempt = {
    # Maintainerr's rule action enum ("DELETE" = 0, ...), not a call.
    "maintainerr/rules/options.nix" = true;
    # Replaces the `nixflix` API key it created; see jellyfin-own-api-key.
    "jellyfin/apiKeyService.nix" = true;
  };
  moduleSources =
    map
      (p: {
        rel = lib.removePrefix "${toString modulesDir}/" (toString p);
        text = builtins.readFile p;
      })
      (
        builtins.filter (p: lib.hasSuffix ".nix" (toString p)) (
          lib.filesystem.listFilesRecursive modulesDir
        )
      );
  removesSomething = src: lib.any (t: lib.hasInfix t src.text) sourceTokens;
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

  # An explicit global "delete" renders exactly what the default renders, with
  # no guard. Whether that is still upstream's behaviour is the next test.
  sync-mode-coverage-explicit-delete-is-default =
    assertTest "sync-mode-coverage-explicit-delete-is-default"
      (
        explicitDelete.texts == defaults.texts
        && guarded defaults == [ ]
        && lib.all (t: !lib.hasInfix "NIXFLIX_SYNC_REFUSED" t) (builtins.attrValues defaults.texts)
      );

  # Delete mode against upstream: every unit's delete-mode text, store paths
  # blanked, hashed and compared with tests/lib/sync-mode-delete-goldens.json,
  # which tests/lib/regen-sync-mode-goldens.sh renders from the merge-base with
  # upstream. Only intentionalDeleteChanges may differ, and only to its pinned
  # hash.
  sync-mode-coverage-delete-matches-upstream =
    assertTest "sync-mode-coverage-delete-matches-upstream"
      (
        report (
          lib.concatMap (
            unit:
            let
              now = currentHashes.${unit} or "<not rendered>";
              before = goldens.units.${unit} or "<no golden>";
              intended = intentionalDeleteChanges.${unit} or null;
            in
            if intended != null then
              lib.optional (
                now != intended.hash
              ) "${unit}: delete-mode hash ${now}, pinned intentional change is ${intended.hash}"
              ++ lib.optional (
                before == intended.hash
              ) "${unit}: listed in intentionalDeleteChanges but matches upstream"
            else
              lib.optional (
                now != before
              ) "${unit}: delete-mode script differs from upstream ${goldens.base} (${before} -> ${now})"
          ) (lib.unique (builtins.attrNames goldens.units ++ builtins.attrNames currentHashes))
        )
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
            lib.filterAttrs (
              _: e:
              builtins.elem e.unit pruningUnits
              && lib.hasInfix e.pattern (beforeCheckpoint refuse.texts.${e.unit})
            ) (exemptions refuse)
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

  # A module that can remove things but never mentions syncMode is a pruning
  # unit nobody wired up; a stale exemption is reported too.
  sync-mode-coverage-source-scan = assertTest "sync-mode-coverage-source-scan" (
    report (
      map (s: "modules/${s.rel}: removes objects but does not use nixflix.syncMode") (
        builtins.filter (
          s: removesSomething s && !(sourceExempt.${s.rel} or false) && !lib.hasInfix "syncMode" s.text
        ) moduleSources
      )
      ++ map (rel: "modules/${rel}: exempt in sourceExempt but no longer removes anything") (
        builtins.filter (rel: !lib.any (s: s.rel == rel && removesSomething s) moduleSources) (
          builtins.attrNames sourceExempt
        )
      )
    )
  );
}
