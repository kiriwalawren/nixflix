{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;

  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };

  pluginResolution = import ./resolvePlugins.nix {
    inherit lib pkgs;
    jellyfinVersion = cfg.package.version;
    inherit (cfg.system) pluginRepositories;
    inherit (cfg) plugins;
  };

  enabledPlugins = pluginResolution.resolvedEnabledPlugins;

  configuredEnabledPlugins = filterAttrs (_name: pluginCfg: pluginCfg.enable) cfg.plugins;

  inherit (pluginResolution) packagePluginDirName;

  packagePluginDirNames = mapAttrsToList (_name: pluginCfg: packagePluginDirName pluginCfg.package) (
    filterAttrs (_name: pluginCfg: pluginCfg.package != null) enabledPlugins
  );
in
{
  imports = [
    ./options.nix
    ./openSubtitles.nix
    ./pluginsService.nix
    ./subbuzz.nix
    ./subtitleExtract.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    warnings = pluginResolution.resolutionWarnings;

    nixflix.jellyfin = {
      plugins.AniDB = mkIf config.nixflix.sonarr-anime.enable {
        package = mkDefault (
          jellyfinPlugins.fromRepo {
            version = "11.0.0.0";
            hash = "sha256-Rtvxq6NxQSrRyhYdsyWXY+SoDPW4S0471gmiLTUjaSk=";
          }
        );
        config = {
          TitlePreference = mkDefault "Localized";
          OriginalTitlePreference = mkDefault "JapaneseRomaji";
          IgnoreSeason = mkDefault false;
          TitleSimilarityThreshold = mkDefault "50";
          MaxGenres = mkDefault "5";
          TidyGenreList = mkDefault true;
          TitleCaseGenres = mkDefault false;
          AnimeDefaultGenre = mkDefault "Anime";
          AniDbRateLimit = mkDefault "2000";
          MaxCacheAge = mkDefault "7";
          AniDbReplaceGraves = mkDefault true;
        };
      };
    };

    assertions = [
      {
        assertion = all (pluginCfg: pluginCfg.package != null) (attrValues configuredEnabledPlugins);
        message = "nixflix.jellyfin.plugins: enabled plugins must define `package`. Use `nixflix.lib.jellyfinPlugins.fromRepo` for repository-backed plugins.";
      }
      {
        assertion = length packagePluginDirNames == length (unique packagePluginDirNames);
        message = "nixflix.jellyfin.plugins contains duplicate package-managed plugin directory names.";
      }
    ];
  };
}
