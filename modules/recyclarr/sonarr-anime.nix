{config, ...}: let
  inherit (config) nixflix;
in {
  sonarr_anime = {
    base_url = "http://127.0.0.1:${toString nixflix.sonarr.config.hostConfig.port}${toString nixflix.sonarr.config.hostConfig.urlBase}";
    api_key._secret = nixflix.sonarr.config.apiKeyPath;
    delete_old_custom_formats = true;
    replace_existing_custom_formats = true;

    quality_definition = {
      type = "anime";
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
        name = "Remux-1080p - Anime";
        reset_unmatched_scores = {
          enabled = true;
        };
        upgrade = {
          allowed = true;
          until_quality = "Bluray-1080p";
          until_score = 10000;
        };
        min_format_score = 100;
        score_set = "anime-sonarr";
        quality_sort = "top";
        qualities = [
          {
            name = "Bluray-1080p";
            qualities = [
              "Bluray-1080p Remux"
              "Bluray-1080p"
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
      }
    ];

    custom_formats = [
      {
        trash_ids = [
          # Scores from TRaSH json — Anime CF/Scoring
          "949c16fe0a8147f50ba82cc2df9411c9" # Anime BD Tier 01 (Top SeaDex Muxers)
          "ed7f1e315e000aef424a58517fa48727" # Anime BD Tier 02 (SeaDex Muxers)
          "096e406c92baa713da4a72d88030b815" # Anime BD Tier 03 (SeaDex Muxers)
          "30feba9da3030c5ed1e0f7d610bcadc4" # Anime BD Tier 04 (SeaDex Muxers)
          "545a76b14ddc349b8b185a6344e28b04" # Anime BD Tier 05 (Remuxes)
          "25d2afecab632b1582eaf03b63055f72" # Anime BD Tier 06 (FanSubs)
          "0329044e3d9137b08502a9f84a7e58db" # Anime BD Tier 07 (P2P/Scene)
          "c81bbfb47fed3d5a3ad027d077f889de" # Anime BD Tier 08 (Mini Encodes)
          "e0014372773c8f0e1bef8824f00c7dc4" # Anime Web Tier 01 (Muxers)
          "19180499de5ef2b84b6ec59aae444696" # Anime Web Tier 02 (Top FanSubs)
          "c27f2ae6a4e82373b0f1da094e2489ad" # Anime Web Tier 03 (Official Subs)
          "4fd5528a3a8024e6b49f9c67053ea5f3" # Anime Web Tier 04 (Official Subs)
          "29c2a13d091144f63307e4a8ce963a39" # Anime Web Tier 05 (FanSubs)
          "dc262f88d74c651b12e9d90b39f6c753" # Anime Web Tier 06 (FanSubs)
          "e3515e519f3b1360cbfc17651944354c" # Anime LQ Groups
          "b4a1b3d705159cdca36d71e57ca86871" # Anime Raws
          "9c14d194486c4014d422adc64092d794" # Dubs Only
          "d2d7b8a9d39413da5f44054080e028a3" # v0
          "273bd326df95955e1b6c26527d1df89b" # v1
          "228b8ee9aa0a609463efca874524a6b8" # v2
          "0e5833d3af2cc5fa96a0c29cd4477feb" # v3
          "4fc15eeb8f2f9a749f918217d4234ad8" # v4
          "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
          "07a32f77690263bb9fda1842db7e273f" # VOSTFR

          # Anime Streaming Services
          "3e0b26604165f463f3e8e192261e7284" # CR
          "1284d18e693de8efe0fe7d6b3e0b9170" # FUNi
          "44a8ee6403071dd7b8a3a8dd3fe8cb20" # VRV
          "89358767a60cc28783cdc3d0be9388a4" # DSNP
          "d34870697c9db575f17700212167be23" # NF
          "d660701077794679fd59e8bdf4ce3a29" # AMZN
          "d54cd2bf1326287275b56bccedb72ee2" # ADN
          "7dd31f3dee6d2ef8eeaa156e23c3857e" # B-Global
          "4c67ff059210182b59cdd41697b8cb08" # Bilibili
          "570b03b3145a25011bf073274a407259" # HIDIVE
          "a370d974bc7b80374de1d9ba7519760b" # ABEMA

          # Main Guide Remux Tier Scoring
          "9965a052eb87b0d10313b1cea89eb451" # Remux Tier 01
          "8a1d0c3d7497e741736761a1da866a2e" # Remux Tier 02

          # Main Guide WEB Tier Scoring
          "e6258996055b9fbab7e9cb2f75819294" # WEB Tier 01
          "58790d4e2fdcd9733aa7ae68ba2bb503" # WEB Tier 02
          "d84935abd3f8556dcd51d4f27e22d0a6" # WEB Tier 03
        ];

        assign_scores_to = [
          {name = "Remux-1080p - Anime";}
        ];
      }
    ];
  };
}
