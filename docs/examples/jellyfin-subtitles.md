---
title: Jellyfin Subtitle Example
---

# Jellyfin Subtitle Example

This example shows how to setup subtitle acquisition in jellyfin.

## Configuration

```nix
{config, ...}: {
  sops.secrets."opensubtitles-com/api-token" = { };
  sops.secrets."opensubtitles-com/password" = { };

  nixflix.jellyfin = {
    enable = true;

    plugins = {
      subbuzz = {
        enable = true;

        config = {
          OpenSubToken._secret = config.sops.secrets."opensubtitles-com/api-token".path;
          EnableOpenSubtitles = true;
          EnableYifySubtitles = true;

          Cache.SubLifeInMinutes = "Always"; # Default is "1 week";
        };
      };

      "Open Subtitles" = {
        enable = true;

        config = {
          Username = "kiriwalawren";
          Password._secret = config.sops.secrets."opensubtitles-com/password".path;
        };
      };

      "Subtitle Extract" = {
        enable = true;

        config.ExtractionDuringLibraryScan = true;
      };
    };

    # Optional
    libraries.Shows = {
      disabledSubtitleFetchers = ["subbuzz"]; # Default: []
      subtitleFetcherOrder = ["subbuzz" "Open Subtitles"]; # Default: ["Open Subtitles" "subbuzz"]
      subtitleDownloadLanguages = [
        "eng"
        "spa"
      ]; # Default: []
      saveSubtitlesWithMedia = true;
      allowEmbeddedSubtitles = "AllowAll";
      requirePerfectSubtitleMatch = true;
      skipSubtitlesIfAudioTrackMatches = false;
      skipSubtitlesIfEmbeddedsubtitlesPresent = true;
    };
  };
}
```
