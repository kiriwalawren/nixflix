---
title: Jellyfin Live TV Example
---

# Jellyfin Live TV Example

This example declares Live TV from an IPTV playlist (M3U) with an XMLTV guide.
Channels are matched to the guide by `tvg-id`.

## Configuration

```nix
{config, ...}: {
  # An IPTV provider URL usually carries your credentials.
  sops.secrets."iptv/playlist-url" = { };

  nixflix.jellyfin = {
    enable = true;

    liveTv = {
      tuners = {
        # A local playlist file.
        local = {
          url = "/var/lib/iptv/channels.m3u";
          friendlyName = "Local channels";
          settings = {
            tunerCount = 0; # 0 = no limit on simultaneous streams
            allowStreamSharing = true;
            enableStreamLooping = true;
            ignoreDts = true;
          };
        };

        # A provider playlist, its URL kept out of the Nix store.
        provider.url._secret = config.sops.secrets."iptv/playlist-url".path;
      };

      listingProviders.guide = {
        path = "/var/lib/iptv/guide.xml"; # or an http(s) URL
        tuners = [ "local" ]; # omit to use it for every tuner
      };
    };
  };
}
```

## How it is applied

The `jellyfin-livetv` service reconciles Jellyfin's Live TV settings at boot
and whenever the declaration changes:

- A declared tuner is matched by its `url`, and a guide by its `path`. Each
  is created if missing and updated in place if it differs. Nothing is
  written when Jellyfin already matches, and the guide is refreshed only
  after a change.
- Changing a tuner's `url` replaces the tuner, and its channels get new ids.
- A tuner or guide that you stop declaring is removed. Tuners and guides
  added by hand in the dashboard are never touched.
- Fields not set in `settings` keep whatever value Jellyfin holds.

Hardware tuners (HDHomeRun, DVB) and Schedules Direct are not covered; set
those up in the dashboard, and this service leaves them alone.
