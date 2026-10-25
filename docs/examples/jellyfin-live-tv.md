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

## A complete example: free English news channels

A working lineup from the broadcasters' own free streams, with a guide. The
guide is the Pluto TV US XMLTV published by
[i.mjh.nz](https://github.com/matthuisman/i.mjh.nz); it is used only for the
schedule. Each channel's `tvg-id` is its id in that guide, which is how
Jellyfin matches a channel to its programmes.

```nix
{pkgs, ...}: let
  # tvg-id = the channel's id in the guide below; tvg-chno = channel number.
  # Stream URLs are the broadcasters' own and can move; these were live on
  # 2026-10-24.
  englishNews = pkgs.writeText "english-news.m3u" ''
    #EXTM3U
    #EXTINF:-1 tvg-id="6508be683a0d700008c534e4" tvg-chno="201" group-title="News",ABC News Live
    https://pb-0n3n2ej0w8pl9.akamaized.net/ABCNewsLive_Disney.m3u8
    #EXTINF:-1 tvg-id="5a6b92f6e22a617379789618" tvg-chno="202" group-title="News",CBS News 24/7
    https://cbsn-us.cbsnstream.cbsnews.com/out/v1/55a8648e8f134e82a470f83d562deeca/master.m3u8
    #EXTINF:-1 tvg-id="54ff7ba69222cb1c2624c584" tvg-chno="203" group-title="News",Bloomberg TV+
    https://bloomberg.com/media-manifest/streams/phoenix-us.m3u8
  '';
in {
  nixflix.jellyfin.liveTv = {
    tuners.english-news = {
      url = "${englishNews}";
      friendlyName = "English news";
      settings = {
        tunerCount = 0; # no limit on simultaneous streams
        allowStreamSharing = true; # several viewers share one upstream stream
        ignoreDts = true; # as on the server these feeds were checked on
      };
    };

    listingProviders.english-news-guide = {
      # A URL works as well as a local file; Jellyfin fetches it itself.
      path = "https://i.mjh.nz/PlutoTV/us.xml";
      tuners = [ "english-news" ];
    };
  };
}
```

To add a channel, add its two lines to the playlist, with its id from the
guide as `tvg-id` (or leave `tvg-id` out for a channel without a guide).

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
