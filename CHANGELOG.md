# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Generic WireGuard VPN support via `nixflix.vpn` (#164)
- Mullvad first-class Tailscale coexistence option (`nixflix.mullvad.tailscale`) (#141).
- Mullvad `persistDevice` option to keep login across reboots (#133).
- Prowlarr indexer proxy support (#139).
- Automatic known-proxy configuration (#123).
- Support for remote Jellyfin instances in Jellyseerr authentication (#125).
- Jellyfin VM tests (#64).
- Jellyseerr module with Radarr/Sonarr integration and VM tests (#43, #73, #74).
- Sonarr anime instance support (#40).
- Initial Jellyfin configuration with library, branding, and encoding services (#24).
- Delay profiles for Starr apps (#20).
- TRaSH guide defaults for SABnzbd (#19).
- Recyclarr with sane defaults, managed quality profiles, and automatic cleanup of unmanaged profiles (#13).
- Download clients configuration service (#8).
- SABnzbd configuration module (#6).
- Prowlarr applications configuration (#5).

### Changed

- **Breaking:** `nixflix.mullvad.*` options have been replaced by
  `nixflix.vpn.*`. Update your configuration accordingly.

- `nixflix.radarr.vpn`, `nixflix.sonarr.vpn`, etc. per-service VPN options now
  reference the generic `nixflix.vpn` namespace rather than Mullvad.

- **Breaking:** `nixflix.mullvad.*` options have been replaced by
  `nixflix.vpn.*`. Update your configuration accordingly.

- `nixflix.radarr.vpn`, `nixflix.sonarr.vpn`, etc. per-service VPN options now
  reference the generic `nixflix.vpn` namespace rather than Mullvad.

- **Breaking (#162):** Recyclarr options schema updated to v8.

  - Remove `replace_existing_custom_formats` from your recyclarr config (dropped in recyclarr v8).
  - New fields available: `trash_id`/`score_set`/`min_upgrade_format_score` on quality profiles, `custom_format_groups`, `media_management`, `sqp-streaming`/`sqp-uhd` quality definition types.
  - If you use `nixflix.inputs.nixpkgs.follows = "nixpkgs"`, run `nix flake update nixpkgs` to get recyclarr 8.5.1.

- Recyclarr timer no longer attempts to start sonarr-anime services when sonarr-anime is disabled (#158).

- Services now wait for the Jellyfin API to be ready before running configuration services (#157).

- ACME certificate configuration added (#154).

- `nixflix.serviceDependencies` now correctly applied to Arr and Jellyfin services (#153).

- **Breaking (#147):** `nixflix.jellyseerr` renamed to `nixflix.seerr`.

  - Update all `nixflix.jellyseerr.*` references to `nixflix.seerr.*` in your configuration.
  - If using `nixflix.inputs.nixpkgs.follows`, update your `flake.lock`.
  - **Without PostgreSQL:** rename `/data/.state/jellyseerr` to `/data/.state/seerr` and update ownership to `seerr:seerr`, or set `nixflix.seerr.dataDir = "/data/.state/jellyseerr"` and change ownership to `seerr:seerr`.
  - **With PostgreSQL:** data is preserved. To keep existing data, set `nixflix.seerr.user = "jellyseerr"` and `nixflix.seerr.group = "jellyseerr"`. If you see collation version warnings, refresh them:
    ```sh
    sudo -u postgres psql -c "ALTER DATABASE jellyseerr REFRESH COLLATION VERSION;"
    # repeat for each database (radarr, sonarr, prowlarr, lidarr, etc.)
    ```

- **Breaking (#146):** `nixflix.jellyfin.apiKey` is now required. Add the option to your configuration before deploying.

- Jellyseerr/Arr PostgreSQL usage scoped to `nixflix.postgres.enable` to avoid conflicting with unrelated PostgreSQL instances (#127).

- **Breaking (#115):** Recyclarr configuration options were refactored. Review the recyclarr module options for the updated structure.

- Arr services now wait for `network-online.target` to fix DNS resolution errors after reboot (#91).

- Recyclarr disabled by default (#80).

- Individual Starr settings overrides added (#87).

- Jellyseerr Radarr/Sonarr config converted from list to attrset (`nixflix.jellyseerr.radarr.<name> = {}`) (#73).

- **Breaking (#107):** Reverse proxy routing switched from path-based to subdomain-based. Services are now served at `<service>.<domain>` instead of `<domain>/<service>`. Update any bookmarks, reverse proxy configuration, or hardcoded URLs accordingly.

- **Breaking (#101):** qBittorrent module rewritten. Review the updated `nixflix.qbittorrent.*` options and update your configuration.

- **Breaking (#90):** Starr service log databases are now separate from the primary databases. Existing logs will not be migrated — a fresh log database will be created on first start. Primary application data is unaffected.

- `_secrets` pattern adopted for all secret paths (#56).

- SABnzbd refactored with updated options (#46).

### Removed

- `modules/mullvad.nix` and all `nixflix.mullvad.*` options.
- Mullvad CLI integration (`mullvad-vpn` service management).
- `tests/vm-tests/mullvad-integration.nix` (replaced by `vpn-integration.nix`).

### Fixed

- qBittorrent category save path now correctly used (#148).
- Download client timing issue causing connection-refused errors at boot (#134).
- Arr services now wait for download client API readiness before proceeding (#128).
- qBittorrent `DefaultSavePath` set to `downloadsDir/default` to prevent permission errors on uncategorized torrent imports (#122).
- Download clients integration fixed (target address was incorrectly set to `0.0.0.0`) (#117).
- Missing folders on NixOS rebuild without reboot (tmpfiles rules and permissions) (#113).
- Secret values with special characters (commas, quotes) no longer mangled by ConfigObj in SABnzbd (#111).
- Jellyseerr authentication after secure curl refactor (#96).
- Prowlarr indexer documentation corrected (#79).
- Username/password download clients for Starr apps (#86).
- Timing issues with Starr services at boot (#84).
- Systemd tmpfiles rules syntax corrected (wrong `root:media` owner format) (#83).
- SABnzbd categories service: API key now passed to curl, redundant URL base slash removed (#68).
- Indexer freeform type fixed; username/password credential option added for Prowlarr (#71).
- Websocket and direct port access for Jellyfin (#37).
