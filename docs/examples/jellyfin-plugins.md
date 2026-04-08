---
title: Jellyfin Plugin Example
---

# Jellyfin Plugin Example

This example shows how to setup a plugin.

## Configuration

```nix
{
  nixflix.jellyfin = {
    system.pluginRepositories = [
      {
        content = {
          name = "Intro Skipper";
          url = "https://intro-skipper.org/manifest.json";
        };
      }
    ];

    plugins."Intro Skipper" = {
      Version = "1.10.11.17";
      ExcludeSeries = "";
      AutoDetectIntros = true;
      AnalyzeSeasonZero = false;
      PreferChromaprint = false;
      CacheFingerprints = true;
      UseAlternativeBlackFrameAnalyzer = false;
      UpdateMediaSegments = true;
      RebuildMediaSegments = true;
      ScanIntroduction = true;
      ScanCredits = true;
      ScanRecap = true;
      ScanPreview = true;
      ScanCommercial = false;
      AnalysisPercent = "25";
      AnalysisLengthLimit = "10";
      FullLengthChapters = false;
      SkipFirstEpisode = false;
      SkipFirstEpisodeAnime = false;
      MinimumIntroDuration = "15";
      MaximumIntroDuration = "120";
      MinimumCreditsDuration = "15";
      MaximumCreditsDuration = "450";
      MaximumMovieCreditsDuration = "900";
      MinimumRecapDuration = "15";
      MaximumRecapDuration = "120";
      MinimumPreviewDuration = "15";
      MaximumPreviewDuration = "120";
      MinimumCommercialDuration = "15";
      MaximumCommercialDuration = "120";
      BlackFrameMinimumPercentage = "85";
      BlackFrameThreshold = "28";
      UseChapterMarkersBlackFrame = true;
      AdjustIntroBasedOnChapters = true;
      AdjustIntroBasedOnSilence = true;
      SnapToKeyframe = true;
      EndSnapThreshold = "2";
      AdjustWindowInward = "5";
      AdjustWindowOutward = "2";
      ChapterAnalyzerIntroductionPattern = "(^|\\s)(Intro|Introduction|OP|Opening)(?!\\sEnd)(\\s|$)";
      ChapterAnalyzerEndCreditsPattern = "(^|\\s)(Credits?|ED|Ending|Outro)(?!\\sEnd)(\\s|$)";
      ChapterAnalyzerPreviewPattern = "(^|\\s)(Preview|PV|Sneak\\s?Peek|Coming\\s?(Up|Soon)|Next\\s+(time|on|episode)|Extra|Teaser|Trailer)(?!\\sEnd)(\\s|:|$)";
      ChapterAnalyzerRecapPattern = "(^|\\s)(Re?cap|Sum{1,2}ary|Prev(ious(ly)?)?|(Last|Earlier)(\\s\\w+)?|Catch[ -]up)(?!\\sEnd)(\\s|:|$)";
      ChapterAnalyzerCommercialPattern = "(^|\\s)(Ad(vert(isement)?)?|Commercial)(?!\\sEnd)(\\s|$)";
      IntroEndOffset = "0";
      IntroStartOffset = "0";
      MaximumFingerprintPointDifferences = 6;
      MaximumTimeSkip = 3.5;
      InvertedIndexShift = 2;
      SilenceDetectionMaximumNoise = "-50";
      SilenceDetectionMinimumDuration = "0.33";
      MaxParallelism = "2";
      ProcessThreads = "0";
      ProcessPriority = "BelowNormal";
      UseFileTransformationPlugin = false;
      SkipbuttonHideDelay = "8";
      EnableMainMenu = true;
      FileTransformationPluginEnabled = false;
    };
  };
}
```

## Settings

Individual plugin settings vary greatly and there is no way I could enumerate them all.

I usually configure them first via the UI, then declare them in Nix
Here are the steps that I follow:

1. Confgure the manifest in `nixflix.jellyfin.system.pluginRepositories`
1. Rebuild
1. Install the desired plugin in the UI
1. Take note of the version of the plugin
1. Restart Jellyfin
1. With the network tab of developer tools open, configure the settings of the desired plugin in the UI
1. Copy the data of the API call
1. Convert it to a nix attribute set
1. Uninstall the application
1. Restart Jellyfin
1. Add the attribute set to `nixflix.jellyfin.plugins.<name> = { ... }`
1. Add the plugin version to `nixflilx.jellyfin.plugins.<name>.Version`
1. Rebuild
