{ config, lib, ... }:
let
  cfg = config.nixflix.jellyfin.plugins.subbuzz;
  secrets = import ../../../lib/secrets { inherit lib; };

  jellyfinPlugins = import ../../../lib/jellyfin-plugins.nix { inherit lib; };

  enumFromAttrs =
    enum_values:
    lib.types.coercedTo (lib.types.enum (lib.attrNames enum_values)) (name: enum_values.${name}) (
      lib.types.enum (lib.attrValues enum_values)
    );
in
{
  options.nixflix.jellyfin.plugins.subbuzz = lib.mkOption {
    type = jellyfinPlugins.mkPluginModule {
      packageDefault = jellyfinPlugins.fromRepo {
        version = "1.4.1.0";
        hash = "sha256-MtHFChAU2ZAtWROSbqxKW8fle8UeAhUt1jIEvw/VZjs=";
      };

      configOption = lib.mkOption {
        type = lib.types.submodule {
          options = {
            EnableAddic7ed = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Addic7ed subtitle provider.";
            };
            EnableOpenSubtitles = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the OpenSubtitles subtitle provider.";
            };
            EnablePodnapisiNet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Podnapisi.NET subtitle provider.";
            };
            EnableSubf2m = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Subf2m subtitle provider.";
            };
            EnableSubdlCom = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Subdl.com subtitle provider.";
            };
            EnableSubscene = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Subscene subtitle provider.";
            };
            EnableSubSource = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the SubSource subtitle provider.";
            };
            EnableSubssabbz = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Subssabbz subtitle provider.";
            };
            EnableSubsunacsNet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Subsunacs.net subtitle provider.";
            };
            EnableYavkaNet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the Yavka.net subtitle provider.";
            };
            EnableYifySubtitles = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable the YIFY Subtitles provider.";
            };
            HashMatchByScore = lib.mkOption {
              type = lib.types.int;
              default = 100;
              description = "Score threshold at which a subtitle is considered a hash match.";
            };
            MinScore = lib.mkOption {
              type = lib.types.int;
              default = 50;
              description = "Minimum score a subtitle must achieve to be downloaded.";
            };
            OpenSubUserName = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Username for authenticating with OpenSubtitles.";
            };
            OpenSubPassword = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = "Password for authenticating with OpenSubtitles.";
            };
            OpenSubApiKey = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = ''
                [API Key](https://www.opensubtitles.com/en/consumers) for the OpenSubtitles service.
              '';
            };
            OpenSubToken = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = "Session token for the OpenSubtitles service. Can be found on the [OpenSubtitles.com profile](https://www.opensubtitles.com/en/users/profile) page.";
            };
            OpenSubUseHash = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "When enabled, the hash of the video file will be sent in the search requests to opensubtitles.com";
            };
            SubEncoding = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  DefaultEncoding = lib.mkOption {
                    type = lib.types.str;
                    default = "utf-8";
                    description = "Use this encoding in cases where automatic encoding detection is disabled or when automatic detection fails.";
                  };
                  AutoDetectEncoding = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Whether to automatically detect the encoding of subtitle files.";
                  };
                  Encodings = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    readOnly = true;
                    internal = true;
                    default = [
                      "ASMO-708"
                      "big5"
                      "cp1025"
                      "cp866"
                      "cp875"
                      "DOS-720"
                      "DOS-862"
                      "EUC-JP"
                      "gb2312"
                      "IBM-Thai"
                      "IBM00858"
                      "IBM00924"
                      "IBM01047"
                      "IBM01140"
                      "IBM01141"
                      "IBM01142"
                      "IBM01143"
                      "IBM01144"
                      "IBM01145"
                      "IBM01146"
                      "IBM01147"
                      "IBM01148"
                      "IBM01149"
                      "IBM037"
                      "IBM1026"
                      "IBM273"
                      "IBM277"
                      "IBM278"
                      "IBM280"
                      "IBM284"
                      "IBM285"
                      "IBM290"
                      "IBM297"
                      "IBM420"
                      "IBM423"
                      "IBM424"
                      "IBM437"
                      "IBM500"
                      "ibm737"
                      "ibm775"
                      "ibm850"
                      "ibm852"
                      "IBM855"
                      "ibm857"
                      "IBM860"
                      "ibm861"
                      "IBM863"
                      "IBM864"
                      "IBM865"
                      "ibm869"
                      "IBM870"
                      "IBM871"
                      "IBM880"
                      "IBM905"
                      "iso-8859-1"
                      "iso-8859-13"
                      "iso-8859-15"
                      "iso-8859-2"
                      "iso-8859-3"
                      "iso-8859-4"
                      "iso-8859-5"
                      "iso-8859-6"
                      "iso-8859-7"
                      "iso-8859-8"
                      "iso-8859-9"
                      "Johab"
                      "koi8-r"
                      "koi8-u"
                      "ks_c_5601-1987"
                      "macintosh"
                      "shift_jis"
                      "us-ascii"
                      "utf-16"
                      "utf-16BE"
                      "utf-32"
                      "utf-32BE"
                      "utf-8"
                      "windows-1250"
                      "windows-1251"
                      "windows-1252"
                      "windows-1253"
                      "windows-1254"
                      "windows-1255"
                      "windows-1256"
                      "windows-1257"
                      "windows-1258"
                      "windows-874"
                      "x-Chinese-CNS"
                      "x-Chinese-Eten"
                      "x-cp20001"
                      "x-cp20003"
                      "x-cp20004"
                      "x-cp20005"
                      "x-cp20261"
                      "x-cp20269"
                      "x-cp20936"
                      "x-cp20949"
                      "x-ebcdic-koreanextended"
                      "x-Europa"
                      "x-IA5"
                      "x-IA5-German"
                      "x-IA5-Norwegian"
                      "x-IA5-Swedish"
                      "x-mac-arabic"
                      "x-mac-ce"
                      "x-mac-chinesetrad"
                      "x-mac-croatian"
                      "x-mac-cyrillic"
                      "x-mac-greek"
                      "x-mac-hebrew"
                      "x-mac-icelandic"
                      "x-mac-japanese"
                      "x-mac-romanian"
                      "x-mac-thai"
                      "x-mac-turkish"
                      "x-mac-ukrainian"
                    ];
                    description = "List of character encodings available for subtitle decoding.";
                  };
                };
              };
              default = { };
              description = "Settings controlling subtitle character encoding detection and conversion.";
            };
            SubPostProcessing = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  EncodeSubtitlesToUTF8 = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Whether to re-encode downloaded subtitles to UTF-8.";
                  };
                  AdjustDuration = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Correct subtitles reading speed when saving.";
                  };
                  AdjustDurationCps = lib.mkOption {
                    type = lib.types.int;
                    default = 15;
                    description = "Characters per second target used when adjusting subtitle duration.";
                  };
                  AdjustDurationExtendOnly = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "When adjusting subtitles do not decrease the original duration.";
                  };
                };
              };
              default = { };
              description = "Settings for post-processing subtitle files after download.";
            };
            Cache = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  Subtitle = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Store the downloaded subtitle files locally to reduce the requests to the providers.";
                  };
                  SubLifeInMinutes = lib.mkOption {
                    type = enumFromAttrs {
                      "1 hour" = 60;
                      "2 hours" = 120;
                      "4 hours" = 240;
                      "8 hours" = 480;
                      "12 hours" = 720;
                      "1 day" = 1440;
                      "2 days" = 2880;
                      "3 days" = 4320;
                      "1 week" = 10080;
                      "2 weeks" = 20160;
                      "3 weeks" = 30240;
                      "30 days" = 43200;
                      "60 days" = 86400;
                      "90 days" = 129600;
                      "Always" = 1000001;
                      "Use cache only in case of error" = 0;
                    };
                    default = "1 week";
                    description = "The subtitles will be downloaded again only when the selected period expires. Usually, once the subtitles are uploaded, they are never updated. Therefore, you may consider increasing the default period to speed up subsequent subtitle downloads.";
                  };
                  Search = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Save results from search requests and reuse them for a specified period of time.";
                  };
                  SearchLifeInMinutes = lib.mkOption {
                    type = enumFromAttrs {
                      "1 hour" = 60;
                      "2 hours" = 120;
                      "4 hours" = 240;
                      "8 hours" = 480;
                      "12 hours" = 720;
                      "1 day" = 1440;
                      "2 days" = 2880;
                      "3 days" = 4320;
                      "4 days" = 5760;
                      "1 week" = 10080;
                      "2 weeks" = 20160;
                      "3 weeks" = 30240;
                      "4 weeks" = 40320;
                      "Use cache only in case of error" = 0;
                    };
                    default = "4 hours";
                    description = "Send search requests to the providers again only after the selected period expires.";
                  };
                  BasePath = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Specify a custom location for the cache files. Leave blank to use the default.";
                  };
                };
              };
              default = { };
              description = "Settings controlling subtitle and search result caching behaviour.";
            };
            SubdlApiKey = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = "Provide your [API Key](https://subdl.com/panel/api) for doing API requests, if left empty provider will be disabled.";
            };
            SubSourceApiKey = secrets.mkSecretOption {
              nullable = false;
              default = "";
              description = "Provide your [API Key](https://subsource.net/dashboard/profile) for doing API requests, if left empty provider will be disabled.";
            };
            SubtitleInfoWithHtml = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Format subtitle information displayed in search dialog using HTML.
                This may cause display issues in clients that doesn't support HTML.
                To use this with Jellyfin web interface you need to patch Jellyfin Web Client.
              '';
            };
          };
        };
        default = { };
        description = "SubBuzz plugin configuration payload as posted to the Jellyfin API.";
      };
    };
    default = { };
  };

  config.nixflix.jellyfin = lib.mkIf cfg.enable {
    system.pluginRepositories = {
      "SubBuzz" = {
        url = "https://raw.githubusercontent.com/josdion/subbuzz/f7c7985a00fe0910f548e3574a592fe8bb7f8ce4/repo/jellyfin_10.11.json";
        hash = "sha256-YrKTQzM1p2THdKpX4azIVAzy4HDd2JARWI4TezqzA5o=";
      };
    };
  };
}
