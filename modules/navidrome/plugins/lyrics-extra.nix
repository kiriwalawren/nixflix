{ config, lib, ... }:
let
  cfg = config.nixflix.navidrome;
  pluginCfg = cfg.plugins."lyrics" or { enable = false; };
in
{
  config = lib.mkMerge [
    {
      nixflix.navidrome.plugins.lyrics = {
        allLibraries = lib.mkDefault true;
        allowWriteAccess = lib.mkDefault true;
        config.durationToleranceSeconds = 5;
      };
    }
    (lib.mkIf (config.nixflix.enable && cfg.enable && (pluginCfg.enable or false)) {
      services.navidrome.settings.LyricsPriority = lib.mkDefault ".ttml,.yaml,.yml,.elrc,.lrc,.srt,.txt,embedded,nd-lyrics";
    })
  ];
}
