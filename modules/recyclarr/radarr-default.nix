{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixflix.recyclarr;
in {
  radarr = {
    radarr_main = {
      base_url = "http://127.0.0.1:${toString config.nixflix.radarr.config.hostConfig.port}${toString config.nixflix.radarr.config.hostConfig.urlBase}";
      api_key._secret = "/run/credentials/recyclarr.service/radarr-api_key";
      delete_old_custom_formats = true;
      replace_existing_custom_formats = true;

      quality_definition = {
        type = "series";
      };

      media_naming = {
        folder = "default";
        movie = {
          rename = true;
          standard = "standard";
        };
      };

      quality_profiles =
        [
          {
            name = "UHD Bluray + WEB";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Bluray-2160p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              {name = "Bluray-2160p";}
              {
                name = "WEB-2160p";
                qualities = ["WEBDL-2160p" "WEBRip-2160p"];
              }
              {name = "Bluray-1080p";}
              {
                name = "WEB-1080p";
                qualities = ["WEBDL-1080p" "WEBRip-1080p"];
              }
              {name = "Bluray-720p";}
            ];
          }
        ]
        ++ optional cfg.radarr.anime.enable {
          name = "Remux-1080p - Anime";

          reset_unmatched_scores = {
            enabled = true;
          };

          upgrade = {
            allowed = true;
            until_quality = "Remux-1080p";
            until_score = 10000;
          };

          min_format_score = 100;
          score_set = "anime-radarr";
          quality_sort = "top";

          qualities = [
            {
              name = "Remux-1080p";
              qualities = [
                "Bluray-1080p"
                "Remux-1080p"
              ];
            }
            {
              name = "WEB 1080p";
              qualities = [
                "WEBDL-1080p"
                "WEBRip-1080p"
                "HDTV-1080p"
              ];
            }
            {name = "Bluray-720p";}
            {
              name = "WEB 720p";
              qualities = [
                "WEBDL-720p"
                "WEBRip-720p"
                "HDTV-720p"
              ];
            }
            {name = "Bluray-576p";}
            {name = "Bluray-480p";}
            {
              name = "WEB 480p";
              qualities = [
                "WEBDL-480p"
                "WEBRip-480p"
              ];
            }
            {name = "DVD";}
            {name = "SDTV";}
          ];
        };

      custom_formats =
        [
          {
            trash_ids = [
              # Unified HDR
              "493b6d1dbec3c3364c59d7607f7e3405" # HDR

              # HQ Release Groups
              "4d74ac4c4db0b64bff6ce0cffef99bf0" # UHD Bluray Tier 01
              "a58f517a70193f8e578056642178419d" # UHD Bluray Tier 02
              "e71939fae578037e7aed3ee219bbe7c1" # UHD Bluray Tier 03
              "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
              "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
              "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03

              # Misc
              "e7718d7a3ce595f289bfee26adc178f5" # Repack/Proper
              "ae43b294509409a6a13919dedd4764c4" # Repack2
              "5caaaa1c08c1742aa4342d8c4cc463f2" # Repack3

              # Unwanted
              "ed38b889b31be83fda192888e2286d83" # BR-DISK
              "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
              "90a6f9a284dff5103f6346090e6280c8" # LQ
              "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
              "dc98083864ea246d05a42df0d05f81cc" # x265 (HD)
              "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
              "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
              "0a3f082873eb454bde444150b70253cc" # Extras
              "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
              "cae4ca30163749b891686f95532519bd" # AV1

              # Streaming Services
              "cc5e51a9e85a6296ceefe097a77f12f4" # BCORE
              "16622a6911d1ab5d5b8b713d5b0036d4" # CRiT
              "2a6039655313bf5dab1e43523b62c374" # MA
            ];

            assign_scores_to = [
              {name = "UHD Bluray + WEB";}
            ];
          }

          {
            trash_ids = [
              # Streaming Services
              "b3b3a6ac74ecbd56bcdbefa4799fb9df" # AMZN
              "40e9380490e748672c2522eaaeb692f7" # ATVP
              "84272245b2988854bfb76a16e60baea5" # DSNP
              "509e5f41146e278f9eab1ddaceb34515" # HBO
              "5763d1b0ce84aff3b21038eea8e9b8ad" # HMAX
              "526d445d4c16214309f0fd2b3be18a89" # Hulu
              "e0ec9672be6cac914ffad34a6b077209" # iT
              "6a061313d22e51e0f25b7cd4dc065233" # MAX
              "170b1d363bd8516fbf3a3eb05d4faff6" # NF
              "c9fd353f8f5f1baf56dc601c4cb29920" # PCOK
              "e36a0ba1bc902b26ee40818a1d59b8bd" # PMTP
              "c2863d2a50c9acad1fb50e53ece60817" # STAN
            ];

            assign_scores_to = [
              {name = "UHD Bluray + WEB";}
            ];
          }
        ]
        ++ optional cfg.radarr.anime.enable {
          # Scores from TRaSH json
          trash_ids = [
            # Anime CF/Scoring
            "fb3ccc5d5cc8f77c9055d4cb4561dded" # Anime BD Tier 01 (Top SeaDex Muxers)
            "66926c8fa9312bc74ab71bf69aae4f4a" # Anime BD Tier 02 (SeaDex Muxers)
            "fa857662bad28d5ff21a6e611869a0ff" # Anime BD Tier 03 (SeaDex Muxers)
            "f262f1299d99b1a2263375e8fa2ddbb3" # Anime BD Tier 04 (SeaDex Muxers)
            "ca864ed93c7b431150cc6748dc34875d" # Anime BD Tier 05 (Remuxes)
            "9dce189b960fddf47891b7484ee886ca" # Anime BD Tier 06 (FanSubs)
            "1ef101b3a82646b40e0cab7fc92cd896" # Anime BD Tier 07 (P2P/Scene)
            "6115ccd6640b978234cc47f2c1f2cadc" # Anime BD Tier 08 (Mini Encodes)
            "8167cffba4febfb9a6988ef24f274e7e" # Anime Web Tier 01 (Muxers)
            "8526c54e36b4962d340fce52ef030e76" # Anime Web Tier 02 (Top FanSubs)
            "de41e72708d2c856fa261094c85e965d" # Anime Web Tier 03 (Official Subs)
            "9edaeee9ea3bcd585da9b7c0ac3fc54f" # Anime Web Tier 04 (Official Subs)
            "22d953bbe897857b517928f3652b8dd3" # Anime Web Tier 05 (FanSubs)
            "a786fbc0eae05afe3bb51aee3c83a9d4" # Anime Web Tier 06 (FanSubs)
            "b0fdc5897f68c9a68c70c25169f77447" # Anime LQ Groups
            "c259005cbaeb5ab44c06eddb4751e70c" # v0
            "5f400539421b8fcf71d51e6384434573" # v1
            "3df5e6dfef4b09bb6002f732bed5b774" # v2
            "db92c27ba606996b146b57fbe6d09186" # v3
            "d4e5e842fad129a3c097bdb2d20d31a0" # v4
            "06b6542a47037d1e33b15aa3677c2365" # Anime Raws
            "9172b2f683f6223e3a1846427b417a3d" # VOSTFR
            "b23eae459cc960816f2d6ba84af45055" # Dubs Only

            # Anime Streaming Services
            "60f6d50cbd3cfc3e9a8c00e3a30c3114" # VRV

            # Main Guide Remux Tier Scoring
            "3a3ff47579026e76d6504ebea39390de" # Remux Tier 01
            "9f98181fe5a3fbeb0cc29340da2a468a" # Remux Tier 02
            "8baaf0b3142bf4d94c42a724f034e27a" # Remux Tier 03

            # Main Guide WEB Tier Scoring
            "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
            "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
            "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03
          ];

          assign_scores_to = [
            {name = "Remux-1080p - Anime";}
          ];
        };
    };
  };
}
