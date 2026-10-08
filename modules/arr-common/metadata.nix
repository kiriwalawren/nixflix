{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.${serviceName};
  inherit (import ./utils.nix { inherit lib pkgs serviceName; })
    usesMediaDirs
    capitalizedName
    isSonarr
    isRadarr
    isLidarr
    mkSecureCurl
    mkWaitForApiScript
    ;

  mkFieldOption =
    default: description:
    mkOption {
      type = types.bool;
      inherit default description;
    };

  mkConsumerOption =
    name: fields:
    mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "the ${name} metadata consumer";
          fields = mkOption {
            type = types.submodule { options = fields; };
            default = { };
            description = "Settings for the ${name} metadata consumer.";
          };
        };
      };
      default = { };
      description = "${name} metadata consumer (Settings → Metadata).";
    };
in
{
  options.nixflix.${serviceName}.config = optionalAttrs usesMediaDirs {
    metadata =
      optionalAttrs isSonarr {
        XbmcMetadata = mkConsumerOption "Kodi (XBMC) / Emby" {
          seriesMetadata = mkFieldOption true "Series Metadata: tvshow.nfo with full series metadata.";
          seriesMetadataEpisodeGuide = mkFieldOption false "Series Metadata Episode Guide: include JSON formatted episode guide element in tvshow.nfo (requires `seriesMetadata`).";
          seriesMetadataUrl = mkFieldOption false "Series Metadata URL: include TheTVDB show URL in tvshow.nfo (can be combined with `seriesMetadata`).";
          episodeMetadata = mkFieldOption true "Episode Metadata: `<filename>.nfo`.";
          episodeImageThumb = mkFieldOption false "Episode Metadata Image Thumbs: include image thumb tags in `<filename>.nfo` (requires `episodeMetadata`).";
          seriesImages = mkFieldOption true "Series Images: fanart.jpg, poster.jpg, banner.jpg.";
          seasonImages = mkFieldOption true "Season Images: season##-poster.jpg, season##-banner.jpg, season-specials-poster.jpg, season-specials-banner.jpg.";
          episodeImages = mkFieldOption true "Episode Images: `<filename>-thumb.jpg`.";
        };
        RoksboxMetadata = mkConsumerOption "Roksbox" {
          episodeMetadata = mkFieldOption true "Episode Metadata: Season##\\filename.xml.";
          seriesImages = mkFieldOption true "Series Images: Series Title.jpg.";
          seasonImages = mkFieldOption true "Season Images: Season ##.jpg.";
          episodeImages = mkFieldOption true "Episode Images: Season##\\filename.jpg.";
        };
        WdtvMetadata = mkConsumerOption "WDTV" {
          episodeMetadata = mkFieldOption true "Episode Metadata: Season##\\filename.xml.";
          seriesImages = mkFieldOption true "Series Images: folder.jpg.";
          seasonImages = mkFieldOption true "Season Images: Season##\\folder.jpg.";
          episodeImages = mkFieldOption true "Episode Images: Season##\\filename.metathumb.";
        };
        PlexMetadata = mkConsumerOption "Plex" {
          seriesPlexMatchFile = mkFieldOption true "Series Plex Match File: creates a .plexmatch file in the series folder.";
          episodeMappings = mkFieldOption false "Episode Mappings: include episode mappings for all files in .plexmatch file.";
        };
      }
      // optionalAttrs isRadarr {
        XbmcMetadata = mkConsumerOption "Kodi (XBMC) / Emby" {
          movieMetadata = mkFieldOption true "Movie Metadata: .nfo with full movie metadata.";
          useMovieNfo = mkFieldOption false "Use movie.nfo: write metadata to movie.nfo instead of the default `<movie-filename>.nfo`.";
          movieMetadataLanguage = mkOption {
            type = types.int;
            default = 1;
            description = "Movie Metadata Language: include selected language if available in .nfo. Radarr language id (1 = English).";
          };
          movieMetadataURL = mkFieldOption false "Movie Metadata URL: include TMDb and IMDb movie URLs in .nfo.";
          addCollectionName = mkFieldOption true "Movie Collection Name: include collection name in .nfo.";
          movieImages = mkFieldOption true "Movie Images: fanart.jpg, poster.jpg.";
        };
        MediaBrowserMetadata = mkConsumerOption "Emby (Legacy)" {
          movieMetadata = mkFieldOption true "Movie Metadata.";
        };
        RoksboxMetadata = mkConsumerOption "Roksbox" {
          movieMetadata = mkFieldOption true "Movie Metadata.";
          movieImages = mkFieldOption true "Movie Images.";
        };
        WdtvMetadata = mkConsumerOption "WDTV" {
          movieMetadata = mkFieldOption true "Movie Metadata.";
          movieImages = mkFieldOption true "Movie Images.";
        };
      }
      // optionalAttrs isLidarr {
        XbmcMetadata = mkConsumerOption "Kodi (XBMC) / Emby" {
          artistMetadata = mkFieldOption true "Artist Metadata: artist.nfo.";
          albumMetadata = mkFieldOption true "Album Metadata: album.nfo.";
          artistImages = mkFieldOption true "Artist Images.";
          albumImages = mkFieldOption true "Album Images.";
        };
        RoksboxMetadata = mkConsumerOption "Roksbox" {
          trackMetadata = mkFieldOption true "Track Metadata: Album\\filename.xml.";
          artistImages = mkFieldOption true "Artist Images: Artist Title.jpg.";
          albumImages = mkFieldOption true "Album Images: Album Title.jpg.";
        };
        WdtvMetadata = mkConsumerOption "WDTV" { trackMetadata = mkFieldOption true "Track Metadata."; };
      };
  };

  config = mkIf (usesMediaDirs && config.nixflix.enable && cfg.enable && cfg.config.apiKey != null) {
    systemd.services."${serviceName}-metadata" = {
      description = "Configure ${serviceName} metadata consumers via API";
      after = [ "${serviceName}-config.service" ] ++ config.nixflix.serviceDependencies;
      requires = [ "${serviceName}-config.service" ] ++ config.nixflix.serviceDependencies;
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = mkWaitForApiScript serviceName cfg.config;
      };

      script = ''
        set -eu

        BASE_URL="http://${cfg.config.hostConfig.bindAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

        echo "Fetching current metadata consumers..."
        METADATA=$(${
          mkSecureCurl cfg.config.apiKey {
            url = "$BASE_URL/metadata";
            extraArgs = "-Sf";
          }
        } 2>/dev/null)

        if [ -z "$METADATA" ]; then
          echo "Failed to fetch metadata consumers"
          exit 1
        fi

        ${concatStringsSep "\n" (
          mapAttrsToList (implementation: consumerConfig: ''
            echo "Configuring metadata consumer: ${implementation}"

            CONSUMER=$(echo "$METADATA" | ${pkgs.jq}/bin/jq --arg impl ${escapeShellArg implementation} \
              '.[] | select(.implementation == $impl)')

            if [ -z "$CONSUMER" ]; then
              echo "Metadata consumer not found: ${implementation}"
              echo "Available: $(echo "$METADATA" | ${pkgs.jq}/bin/jq -r '[.[].implementation] | join(", ")')"
              exit 1
            fi

            CONSUMER_ID=$(echo "$CONSUMER" | ${pkgs.jq}/bin/jq -r '.id')
            DESIRED=${escapeShellArg (builtins.toJSON consumerConfig)}

            NEW_CONSUMER=$(echo "$CONSUMER" | ${pkgs.jq}/bin/jq --argjson desired "$DESIRED" \
              '.enable = $desired.enable
               | .fields |= map(.name as $name
                   | if $desired.fields | has($name) then .value = $desired.fields[$name] else . end)')

            PUT_STATUS=$(${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/metadata/$CONSUMER_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_CONSUMER";
                extraArgs = ''-So /tmp/put_response -w "%{http_code}"'';
              }
            })
            if [ "$PUT_STATUS" -ge 400 ]; then
              echo "PUT failed (HTTP $PUT_STATUS):"
              cat /tmp/put_response
              exit 1
            fi

            echo "Metadata consumer configured: ${implementation}"
          '') cfg.config.metadata
        )}

        echo "${capitalizedName} metadata configuration complete"
      '';
    };
  };
}
