{config, ...}: let
  inherit (config) nixflix;
in {
  radarr_main = {
    base_url = "http://127.0.0.1:${toString nixflix.radarr.config.hostConfig.port}${toString nixflix.radarr.config.hostConfig.urlBase}";
    api_key._secret = nixflix.radarr.config.apiKeyPath;
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

    quality_profiles = [
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
    ];

    custom_formats = [
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
    ];
  };
}
