{ lib, ... }:
let

  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };
in
{
  options.nixflix.jellyfin.plugins."Subtitle Extract" = lib.mkOption {
    type = jellyfinPlugins.mkPluginModule {
      packageDefault = jellyfinPlugins.fromRepo {
        version = "7.0.0.0";
        hash = "sha256-vnSYKFf0L6Bk6jOegxs/Rk+2n5oEAQpxTbLqxNpYh2o=";
      };

      configOption = lib.mkOption {
        type = lib.types.submodule {
          options = {
            ExtractionDuringLibraryScan = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to extract embedded subtitles and attachments during a library scan.";
            };
            SelectedSubtitlesLibraries = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of libraries from which subtitles will be extracted.";
            };
            SelectedAttachmentsLibraries = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of libraries from which attachments will be extracted.";
            };
            AllSubtitleCodecs = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    Value = lib.mkOption {
                      type = lib.types.str;
                      description = "Codec identifier used internally to reference the subtitle format.";
                    };
                    Text = lib.mkOption {
                      type = lib.types.str;
                      description = "Human-readable display name and description of the subtitle format.";
                    };
                  };
                }
              );
              default = [
                {
                  Value = "ass";
                  Text = "ASS (Advanced SSA) subtitle (.ass & .ssa files - often found on anime)";
                }
                {
                  Value = "DVDSUB";
                  Text = "DVD subtitles";
                }
                {
                  Value = "subrip";
                  Text = "SubRip subtitle (.srt files - most common type of subtitles)";
                }
                {
                  Value = "PGSSUB";
                  Text = "HDMV Presentation Graphic Stream subtitles (often found on Blu-ray)";
                }
                {
                  Value = "DVBSUB";
                  Text = "DVB subtitles";
                }
                {
                  Value = "eia_608";
                  Text = "EIA-608 closed captions";
                }
                {
                  Value = "jacosub";
                  Text = "JACOsub subtitle";
                }
                {
                  Value = "microdvd";
                  Text = "MicroDVD subtitle";
                }
                {
                  Value = "mov_text";
                  Text = "MOV text";
                }
                {
                  Value = "mpl2";
                  Text = "MPL2 subtitle";
                }
                {
                  Value = "pjs";
                  Text = "PJS (Phoenix Japanimation Society) subtitle";
                }
                {
                  Value = "realtext";
                  Text = "RealText subtitle";
                }
                {
                  Value = "sami";
                  Text = "SAMI subtitle";
                }
                {
                  Value = "stl";
                  Text = "Spruce subtitle format";
                }
                {
                  Value = "subviewer";
                  Text = "SubViewer subtitle";
                }
                {
                  Value = "subviewer1";
                  Text = "SubViewer v1 subtitle";
                }
                {
                  Value = "text";
                  Text = "raw UTF-8 text";
                }
                {
                  Value = "vplayer";
                  Text = "VPlayer subtitle";
                }
                {
                  Value = "webvtt";
                  Text = "WebVTT subtitle";
                }
                {
                  Value = "xsub";
                  Text = "XSUB";
                }
              ];
              description = "Full list of all supported subtitle codecs with their display names. Only works when `IsAdvancedMode = true;`.";
            };
            SelectedCodecs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "ass"
                "DVDSUB"
                "subrip"
                "PGSSUB"
                "DVBSUB"
                "eia_608"
                "jacosub"
                "microdvd"
                "mov_text"
                "mpl2"
                "pjs"
                "realtext"
                "sami"
                "stl"
                "subviewer"
                "subviewer1"
                "text"
                "vplayer"
                "webvtt"
                "xsub"
              ];
              description = "Limit subtitle extraction to media with all subtitle streams matching the selected codecs. Only works when `IsAdvancedMode = true;`.";
            };
            IsAdvancedMode = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable advanced codec selection for fine-grained control";
            };
            IncludeTextSubtitles = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Includes: SRT, ASS/SSA, WebVTT, and other text-based subtitle formats.
                It will extract subtitles from medias containing only text subtitles.
              '';
            };
            IncludeGraphicalSubtitles = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Includes: DVD subtitles (VOBSUB), Blu-ray subtitles (PGS), and other image-based formats.
                It will extract subtitles from medias containing at least one graphical subtitle.
              '';
            };
          };
        };
        default = { };
        description = ''
          Plugin to automatically extract embedded subtitles.
        '';
      };
    };
    default = { };
  };
}
