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
| `"refuse"` | nothing happens | the unit fails before changing anything and lists them |

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
not declare, it prints what it found, exits with code **78**, and changes nothing
in that service: no creates, no updates, no deletes. For example:

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

For each object listed, either declare it in your configuration (it is then
updated, never deleted), or remove it by hand in the service's UI. Rebuild until
no unit fails. Exit code 78 is the only one nixflix uses for this, so a unit
that fails with any other code failed for a different reason (the API was not
reachable, a request was rejected) and its log says why.

### 2. Move to `keep`

Once a refuse run is clean, or when you decide some undeclared objects should
just stay, switch to `keep`:

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

`keep` is a fine place to stay if you want nixflix to manage some things while
you keep managing others in the UI.

### 3. Move to `delete` when you are ready

When your configuration describes everything you want, remove the `syncMode`
line (or set it to `"delete"`). From then on nixflix removes anything that is
not declared, so the services always match the configuration.

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

Every option defaults to `nixflix.syncMode`. `<arr>` is `radarr`, `sonarr`,
`sonarr-anime` or `lidarr`.

| Option | Governs | Unit |
| --- | --- | --- |
| `nixflix.<arr>.syncMode.rootFolders` | root folders | `<arr>-rootfolders` |
| `nixflix.<arr>.syncMode.delayProfiles` | delay profiles (the built-in default profile, id 1, is never deleted) | `<arr>-delayprofiles` |
| `nixflix.<arr>.syncMode.downloadClients` | download clients | `<arr>-downloadclients` |
| `nixflix.<arr>.syncMode.notifications` | notifications (Connect) | `<arr>-notifications` |
| `nixflix.prowlarr.syncMode.downloadClients` | download clients | `prowlarr-downloadclients` |
| `nixflix.prowlarr.syncMode.indexers` | indexers | `prowlarr-indexers` |
| `nixflix.prowlarr.syncMode.indexerProxies` | indexer proxies | `prowlarr-indexer-proxies` |
| `nixflix.prowlarr.syncMode.applications` | applications (the *arrs Prowlarr syncs to) | `prowlarr-applications` |
| `nixflix.lidarr.syncMode.qualityProfiles` | quality profiles | `lidarr-qualityprofiles` |
| `nixflix.lidarr.syncMode.metadataProfiles` | metadata profiles | `lidarr-metadataprofiles` |
| `nixflix.seerr.syncMode.radarr` | Radarr servers | `seerr-radarr` |
| `nixflix.seerr.syncMode.sonarr` | Sonarr servers | `seerr-sonarr` |
| `nixflix.seerr.syncMode.jellyfinLibraries` | enabled Jellyfin libraries that do not match `nixflix.seerr.jellyfin.libraryFilter` (disabled, not deleted; only with `enableAllLibraries = false`) | `seerr-libraries` |
| `nixflix.jellyfin.syncMode.libraries` | libraries nixflix created earlier (tracked in its state file; libraries you made in the UI are never touched) | `jellyfin-libraries` |
| `nixflix.jellyfin.syncMode.libraryPaths` | paths of declared libraries | `jellyfin-libraries` |
| `nixflix.jellyfin.syncMode.plugins` | plugin directories nixflix installed earlier (state file) | `jellyfin-plugins` |
| `nixflix.jellyfin.syncMode.liveTv` | Live TV tuners and guides nixflix created earlier (state file) | `jellyfin-livetv` |
| `nixflix.maintainerr.syncMode.radarr` | Radarr servers | `maintainerr-settings` |
| `nixflix.maintainerr.syncMode.sonarr` | Sonarr servers | `maintainerr-settings` |
| `nixflix.maintainerr.syncMode.rules` | rule groups | `maintainerr-rules` |
| `nixflix.maintainerr.syncMode.overlayTemplates` | overlay templates (presets are never touched) | `maintainerr-overlay-templates` |
| `nixflix.usenetClients.sabnzbd.syncMode.categories` | categories (the built-in `*` is never touched) | `sabnzbd-categories` |
| `nixflix.torrentClients.qbittorrent.syncMode.categories` | categories in `categories.json` | `qbittorrent` (its `preStart`) |
| `nixflix.recyclarr.syncMode.qualityProfiles` | quality profiles not listed in `cleanupUnmanagedProfiles.managedProfiles` (only with `cleanupUnmanagedProfiles.enable`) | `recyclarr-cleanup-profiles` |
| `nixflix.recyclarr.syncMode.customFormats` | the default of each instance's `delete_old_custom_formats` (see below) | `recyclarr` |

## Not covered / caveats

- **sabnzbd.ini is rewritten on every SABnzbd start.** `sabnzbd.service`
  regenerates `sabnzbd.ini` from the declared settings each time it starts, so
  servers, RSS feeds and settings added in the SABnzbd UI are dropped in every
  mode. `syncMode` only covers SABnzbd **categories**. Declare servers and feeds
  in `nixflix.usenetClients.sabnzbd.settings` before you enable it.
- **qBittorrent `refuse` stops qBittorrent from starting.** Categories are synced
  in the `preStart` of `qbittorrent.service`, so a refused sync fails the daemon
  itself, not a separate unit, until the undeclared categories are declared or
  removed from `categories.json`.
- **Recyclarr `customFormats = "refuse"` cannot be enforced.** Recyclarr decides
  which custom formats it deletes (only ones it synced itself), and nixflix cannot
  inspect that before Recyclarr runs. `"refuse"` behaves like `"keep"`
  (`delete_old_custom_formats` defaults to `false`) and produces an evaluation
  warning. Only `"delete"` defaults it to `true`.
- **A changed Jellyfin `collectionType` recreates the library.** Jellyfin cannot
  change the type of an existing library, so a declared library whose
  `collectionType` changed is deleted and created again, in every mode. That only
  ever happens to a library you declared.
- **Jellyfin `libraries` only know what nixflix made.** The libraries guard works
  from nixflix's state file, so libraries created in the Jellyfin UI are never
  listed, kept or deleted.
- **Seerr's library check makes one request first.** Seerr only returns the
  Jellyfin library list through `POST /api/v1/settings/jellyfin/library/sync`,
  which refreshes Seerr's copy of the list (it keeps each library's enabled flag).
  `seerr-libraries` sends that one request before its guard; nothing is enabled or
  disabled before the guard.
- **A refused unit blocks the units that require it.** systemd does not start a
  unit whose `requires` failed, so one refusal can hold back units that have
  nothing undeclared. For example, `lidarr-rootfolders` requires
  `lidarr-qualityprofiles`, so a refused quality profile sync also leaves root
  folders unsynced. Clear the first failure and the rest follow.
- **Exit code 78 is not retried.** A refused unit exits with 78 (`EX_CONFIG`).
  Units that restart on failure (`prowlarr-indexer-proxies`) set
  `RestartPreventExitStatus = 78`, so a refusal fails once instead of looping.
  Rebuild, or `systemctl restart` the unit, after fixing what it listed.
- **`delete` is unchanged.** With the default, every unit renders exactly the
  script it did before `syncMode` existed, apart from a bug fix in
  `sabnzbd-categories` (category names with spaces or `*` were mangled).
