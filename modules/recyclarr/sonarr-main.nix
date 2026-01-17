{config, ...}: let
  inherit (config) nixflix;
in {
  sonarr_main = {
    base_url = "http://127.0.0.1:${toString nixflix.sonarr.config.hostConfig.port}${toString nixflix.sonarr.config.hostConfig.urlBase}";
    api_key._secret = nixflix.sonarr.config.apiKeyPath;
    delete_old_custom_formats = true;
    replace_existing_custom_formats = true;

    quality_definition = {
      type = "series";
    };

    media_naming = {
      series = "default";
      season = "default";
      episodes = {
        rename = true;
        standard = "default";
        daily = "default";
        anime = "default";
      };
    };

    quality_profiles = [
      {
        name = "WEB-1080p";

        reset_unmatched_scores = {
          enabled = true;
        };

        upgrade = {
          allowed = true;
          until_quality = "WEB 1080p";
          until_score = 10000;
        };

        min_format_score = 0;
        quality_sort = "top";

        qualities = [
          {
            name = "WEB 1080p";
            qualities = [
              "WEBDL-1080p"
              "WEBRip-1080p"
            ];
          }
          {name = "Bluray-1080p";}
          {name = "HDTV-1080p";}
          {
            name = "WEB 720p";
            qualities = [
              "WEBDL-720p"
              "WEBRip-720p"
            ];
          }
          {name = "Bluray-720p";}
          {name = "HDTV-720p";}
        ];
      }
    ];

    custom_formats = [
      {
        trash_ids = [
          # Unwanted
          "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
          "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
          "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
          "47435ece6b99a0b477caf360e79ba0bb" # x265 (HD)
          "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
          "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1

          # Misc
          "ec8fa7296b64e8cd390a1600981f3923" # Repack/Proper
          "eb3d5cc0a2be0db205fb823640db6a3c" # Repack v2
          "44e7c4de10ae50265753082e5dc76047" # Repack v3

          # Streaming Services
          "d660701077794679fd59e8bdf4ce3a29" # AMZN
          "f67c9ca88f463a48346062e8ad07713f" # ATVP
          "77a7b25585c18af08f60b1547bb9b4fb" # CC
          "36b72f59f4ea20aad9316f475f2d9fbb" # DCU
          "dc5f2bb0e0262155b5fedd0f6c5d2b55" # DSCP
          "89358767a60cc28783cdc3d0be9388a4" # DSNP
          "7a235133c87f7da4c8cccceca7e3c7a6" # HBO
          "a880d6abc21e7c16884f3ae393f84179" # HMAX
          "f6cce30f1733d5c8194222a7507909bb" # Hulu
          "0ac24a2a68a9700bcb7eeca8e5cd644c" # iT
          "81d1fbf600e2540cee87f3a23f9d3c1c" # MAX
          "d34870697c9db575f17700212167be23" # NF
          "1656adc6d7bb2c8cca6acfb6592db421" # PCOK
          "c67a75ae4a1715f2bb4d492755ba4195" # PMTP
          "ae58039e1319178e6be73caab5c42166" # SHO
          "1efe8da11bfd74fbbcd4d8117ddb9213" # STAN
          "9623c5c9cac8e939c1b9aedd32f640bf" # SYFY
          "43b3cf48cb385cd3eac608ee6bca7f09" # UHD Streaming Boost
          "218e93e5702f44a68ad9e3c6ba87d2f0" # HD Streaming Boost

          # HQ Source Groups
          "e6258996055b9fbab7e9cb2f75819294" # WEB Tier 01
          "58790d4e2fdcd9733aa7ae68ba2bb503" # WEB Tier 02
          "d84935abd3f8556dcd51d4f27e22d0a6" # WEB Tier 03
          "d0c516558625b04b363fa6c5c2c7cfd4" # WEB Scene
        ];
        assign_scores_to = [
          {name = "WEB-1080p";}
        ];
      }

      {
        trash_ids = [
          "923b6abef9b17f937fab56cfcf89e1f1" # DV (w/o HDR fallback)
          "b337d6812e06c200ec9a2d3cfa9d20a7" # DV (ALL - Excludes all DV releases)
        ];

        assign_scores_to = [
          {name = "WEB-1080p";}
        ];
      }
    ];
  };
}
