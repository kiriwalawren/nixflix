---
title: Adopting an Existing Install
---

# Adopting an Existing Install

Nixflix treats your configuration as the source of truth. By default its sync
units delete anything a service has that you did not declare: a root folder you
added in the Radarr UI, an indexer you set up in Prowlarr by hand, a Seerr server,
a Maintainerr rule. On a fresh install that is what you want. On an install you
have been running for years, the first rebuild would remove everything you have
not written down yet.

`nixflix.syncMode` controls this. It has three modes:

| Mode | Declared objects | Undeclared objects |
| --- | --- | --- |
| `"delete"` (default) | created and updated | deleted |
| `"keep"` | created and updated | left alone, listed in the unit's log |
| `"refuse"` | created and updated, as in `"delete"`, when nothing is undeclared | if any exist, the unit lists them and fails before changing anything |

`"refuse"` flags exactly what `"delete"` would delete on that run, no more and
no less. When `"delete"` would delete nothing, `"refuse"` passes and the unit
syncs your declared objects like it always does.

The global option sets the default for every collection. Each collection can be
overridden with `nixflix.<service>.syncMode.<collection>`, see the
[table below](#every-collection).

## The safe path

### 1. Start with `refuse`

```nix
{
  nixflix = {
    enable = true;
    syncMode = "refuse";
    # ... your services, as close to what you run today as you can get ...
  };
}
```

Rebuild. Every sync unit first reads the live state. If it finds anything you did
not declare, it prints what it found, exits with code **78**, and that unit
changes nothing: no creates, no updates, no deletes. For example:

```text
nixflix: radarr-rootfolders: refusing to sync: 1 root folders exist that are not declared (nixflix.radarr.syncMode.rootFolders = "refuse"). Nothing was changed.
nixflix:   - /media/old-movies (id 2)
nixflix: declare them (see nixflix.radarr.syncMode.rootFolders), or set it to "keep" or "delete".
```

`nixos-rebuild switch` reports the failed units. List them and read their logs:

```bash
systemctl list-units --failed 'radarr-*' 'sonarr-*' 'lidarr-*' 'prowlarr-*' \
  'seerr-*' 'jellyfin-*' 'maintainerr-*' 'sabnzbd-*' 'qbittorrent*' 'recyclarr-*'
journalctl -o cat -u radarr-rootfolders.service | grep '^nixflix:'
```

A unit with several collections checks all of them before it stops, so one run
lists everything that blocks it.

A refusal only holds back the unit that refused. The other sync units of the same
service still run when their own checks pass: a refused `radarr-rootfolders` does
not stop `radarr-config`, `radarr-delayprofiles` or `radarr-downloadclients`
from creating and updating what you declared. The exception is a unit that
`requires` the refused one: systemd does not start it (see
[the caveats](#not-covered-caveats)).

For each object listed, either declare it in your configuration (it is then
updated, never deleted), or remove it by hand in the service's UI. Rebuild until
no unit fails. Exit code 78 is the only one nixflix uses for this, so a unit
that fails with any other code failed for a different reason (the API was not
reachable, a request was rejected) and its log says why.

### 2. Switch to `delete` once `refuse` passes

When a rebuild finishes with no refused unit, `"delete"` would delete nothing
on that run: `"refuse"` flags exactly what `"delete"` deletes. That is the
point to let nixflix enforce the configuration. Remove the `syncMode` line (or
set it to `"delete"`) and rebuild. From then on nixflix removes anything that is
not declared, so the services always match the configuration.

Switch soon after the clean run. Something added in a UI in between is deleted
by the first `"delete"` run; if in doubt, rebuild once more with `"refuse"`
first.

### Or stay on `keep`

If you want nixflix to manage some things while you keep managing others in
the UI, use `keep` instead of `delete`, globally or per collection:

```nix
{
  nixflix.syncMode = "keep";
}
```

Declared objects are created and updated; undeclared ones are left as they are
and logged on every run:

```text
nixflix: radarr-rootfolders: keeping 1 undeclared root folders (nixflix.radarr.syncMode.rootFolders = "keep"): /media/old-movies
```

`keep` also gets a rebuild through while you are still declaring things, at the
cost of not telling you about them by failing.

You can also move one collection at a time:

```nix
{
  nixflix = {
    syncMode = "refuse";
    # Root folders are declared already; let nixflix enforce them.
    radarr.syncMode.rootFolders = "delete";
    # Indexers I add by hand in Prowlarr should stay.
    prowlarr.syncMode.indexers = "keep";
  };
}
```

## Every collection

Every option defaults to `nixflix.syncMode`; setting one explicitly overrides
the global for that collection only. `<arr>` is `radarr`, `sonarr`,
`sonarr-anime` or `lidarr`.

| Option | Governs | Unit |
| --- | --- | --- |
| `nixflix.<arr>.syncMode.rootFolders` | root folders | `<arr>-rootfolders` |
| `nixflix.<arr>.syncMode.delayProfiles` | delay profiles, matched by `id` (the built-in default profile, id 1, is always declared and never deleted) | `<arr>-delayprofiles` |
| `nixflix.<arr>.syncMode.downloadClients` | download clients | `<arr>-downloadclients` |
| `nixflix.<arr>.syncMode.notifications` | notifications (Connect) | `<arr>-notifications` |
| `nixflix.prowlarr.syncMode.downloadClients` | download clients | `prowlarr-downloadclients` |
| `nixflix.prowlarr.syncMode.indexers` | indexers | `prowlarr-indexers` |
| `nixflix.prowlarr.syncMode.indexerProxies` | indexer proxies | `prowlarr-indexer-proxies` |
| `nixflix.prowlarr.syncMode.applications` | applications (the *arrs Prowlarr syncs to) | `prowlarr-applications` |
| `nixflix.lidarr.syncMode.qualityProfiles` | quality profiles | `lidarr-qualityprofiles` |
| `nixflix.lidarr.syncMode.metadataProfiles` | metadata profiles | `lidarr-metadataprofiles` |
| `nixflix.seerr.syncMode.radarr` | Radarr servers (see the name-matching caveat) | `seerr-radarr` |
| `nixflix.seerr.syncMode.sonarr` | Sonarr servers (see the name-matching caveat) | `seerr-sonarr` |
| `nixflix.seerr.syncMode.jellyfinLibraries` | enabled Jellyfin libraries that do not match `nixflix.seerr.jellyfin.libraryFilter` (disabled, not deleted; only with `enableAllLibraries = false`) | `seerr-libraries` |
| `nixflix.jellyfin.syncMode.libraries` | libraries nixflix created earlier (tracked in its state file), and the recreate of a declared library whose `collectionType` differs | `jellyfin-libraries` |
| `nixflix.jellyfin.syncMode.libraryPaths` | paths of declared libraries | `jellyfin-libraries` |
| `nixflix.jellyfin.syncMode.plugins` | plugin directories nixflix installed earlier (state file) | `jellyfin-plugins` |
| `nixflix.jellyfin.syncMode.liveTv` | Live TV tuners and guides nixflix created earlier (state file) | `jellyfin-livetv` |
| `nixflix.maintainerr.syncMode.radarr` | Radarr servers | `maintainerr-settings` |
| `nixflix.maintainerr.syncMode.sonarr` | Sonarr servers | `maintainerr-settings` |
| `nixflix.maintainerr.syncMode.rules` | rule groups | `maintainerr-rules` |
| `nixflix.maintainerr.syncMode.overlayTemplates` | overlay templates (presets are never touched) | `maintainerr-overlay-templates` |
| `nixflix.usenetClients.sabnzbd.syncMode.categories` | categories, matched ignoring ASCII case (the built-in `*` is never touched) | `sabnzbd-categories` |
| `nixflix.torrentClients.qbittorrent.syncMode.categories` | categories in `categories.json` | `qbittorrent` (its `preStart`) |
| `nixflix.recyclarr.syncMode.qualityProfiles` | quality profiles not listed in `cleanupUnmanagedProfiles.managedProfiles` (only with `cleanupUnmanagedProfiles.enable`; an instance where none of the listed profiles exists is skipped, as `"delete"` skips it) | `recyclarr-cleanup-profiles` |
| `nixflix.recyclarr.syncMode.customFormats` | the default of each instance's `delete_old_custom_formats`; defaults to `"keep"` under a global `"refuse"` (see below) | `recyclarr` |

## Not covered / caveats

- **Units that never delete have no `syncMode`.** The other sync units only
  create and update what you declared and never remove anything: the *arr host
  config, media management, metadata consumers and metadata provider, Jellyfin
  users, system, branding and metadata settings, Seerr's Jellyfin connection,
  Navidrome users and plugin settings, and slskd's settings.
  `jellyfin-api-key` replaces only the API key named `nixflix`, which it
  created itself.

- **sabnzbd.ini is rewritten on every SABnzbd start.** `sabnzbd.service`
  regenerates `sabnzbd.ini` from the declared settings each time it starts, so
  servers, RSS feeds and settings added in the SABnzbd UI are dropped in every
  mode. `syncMode` only covers SABnzbd **categories**. Declare servers and feeds
  in `nixflix.usenetClients.sabnzbd.settings` before you enable it.
- **qBittorrent `refuse` stops qBittorrent from starting.** Categories are synced
  in the `preStart` of `qbittorrent.service`, so a refused sync fails the daemon
  itself, not a separate unit, until the undeclared categories are declared or
  removed from `categories.json`.
- **Recyclarr custom formats cannot be refused.** Recyclarr decides which custom
  formats it deletes (only ones it synced itself), and nixflix cannot inspect that
  before Recyclarr runs. A global `nixflix.syncMode = "refuse"` therefore gives
  `nixflix.recyclarr.syncMode.customFormats = "keep"` (`delete_old_custom_formats`
  defaults to `false`), without a warning. Setting
  `customFormats = "refuse"` explicitly behaves the same and produces an
  evaluation warning. Only `"delete"` defaults it to `true`.
- **Declaring a Jellyfin library by name adopts the one you already have.** A
  library you created in the Jellyfin UI is matched by its name. Once you declare
  that name, nixflix manages it like one it created: its library options are
  overwritten with the declared ones, its paths are pruned according to
  `nixflix.jellyfin.syncMode.libraryPaths`, and if its `collectionType` differs
  from the declared one it is deleted and created again (Jellyfin cannot change
  the type of a library), which drops Jellyfin's metadata for it. Under
  `"refuse"` the option overwrite still happens once nothing blocks the unit,
  because it changes a declared library; the undeclared paths
  (`libraryPaths = "refuse"`) and the recreate (`libraries = "refuse"`) are
  refused and listed instead. Libraries you made in the UI and do not declare are
  never listed, kept or deleted, because the libraries guard works from
  nixflix's state file.
- **The `collectionType` recreate follows `nixflix.jellyfin.syncMode.libraries`.**
  Under `"delete"` the library is deleted and created again. Under `"refuse"`
  the unit refuses and lists it, by name and types only:
  `nixflix:   - Movies (collectionType tvshows -> movies)`. Under `"keep"` it
  is left as it is (its options and paths are not updated either) and the log
  says `not recreating library Movies`. Fix the declared `collectionType`, or
  delete the library in Jellyfin, to clear it. With `libraries = "delete"` and
  `libraryPaths = "refuse"` the recreate still happens, and the recreated
  library has only its declared paths.
- **Delay profiles are matched by `id`.** A live delay profile whose `id` equals
  a declared `id` counts as declared, whatever its settings, so under `"keep"`
  and `"refuse"` it is overwritten (PUT) with the declared profile rather than
  listed. Check the ids in the *arr before you declare delay profiles.
- **Names are compared exactly, with two exceptions.** Most collections match a
  live object to a declaration by exact, case-sensitive name (or path, or id).
  SABnzbd stores category names lowercased, so its categories match ignoring
  ASCII case: a declared `Movies` is the live `movies`. Seerr's Radarr and
  Sonarr servers keep the historical `delete` matching, which treats a live
  server as declared when its name is part of a declared name: with
  `"Radarr 4K"` declared, live servers named `Radarr` or `4K` are neither
  deleted nor refused.
- **Seerr's library check makes one request first.** Seerr only returns the
  Jellyfin library list through `POST /api/v1/settings/jellyfin/library/sync`,
  which refreshes Seerr's copy of the list (it keeps each library's enabled flag).
  `seerr-libraries` sends that one request before its guard; nothing is enabled or
  disabled before the guard.
- **A refused unit blocks the units that require it.** systemd does not start a
  unit whose `requires` failed, so one refusal can hold back units that have
  nothing undeclared. For example, `lidarr-rootfolders` requires
  `lidarr-qualityprofiles`, so a refused quality profile sync also leaves root
  folders unsynced, and `seerr-radarr`/`seerr-sonarr` require
  `recyclarr-cleanup-profiles` when profile cleanup is enabled. Units that only
  `want` or order after it still run. Clear the first failure and the rest
  follow.
- **qBittorrent's `categories.json` is read like qBittorrent reads it.** A
  missing, empty or whitespace-only file holds no categories. So does a file
  that is not a single JSON object; nixflix logs a warning for that one. In all
  of these cases there is nothing undeclared: `"refuse"` passes and `"keep"`
  writes the declared categories.
- **Exit code 78 is not retried.** A refused unit exits with 78 (`EX_CONFIG`).
  Units that restart on failure (`prowlarr-indexer-proxies`) set
  `RestartPreventExitStatus = 78`, so a refusal fails once instead of looping.
  Rebuild, or `systemctl restart` the unit, after fixing what it listed.
- **`delete` is unchanged.** With the default, every unit renders exactly the
  script it did before `syncMode` existed, apart from bug fixes in
  `sabnzbd-categories` (category names with spaces or `*` were mangled, and
  names were matched as case-sensitive regular expressions).
