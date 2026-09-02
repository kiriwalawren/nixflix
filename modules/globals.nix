{ lib, ... }:
with lib;
{
  options.nixflix.globals = mkOption {
    type = types.attrs;
    description = "Global values to be used by nixflix services";
    default = { };
  };

  config.nixflix.globals = {
    libraryOwner.user = "root";
    libraryOwner.group = "media";

    uids = {
      autobrr = 188;
      bazarr = 232;
      beets = 257;
      cross-seed = 183;
      jellyfin = 146;
      lidarr = 306;
      maintainerr = 322;
      navidrome = 282;
      prowlarr = 293;
      qbittorrent = 70;
      radarr = 275;
      recyclarr = 269;
      sabnzbd = 38;
      seerr = 262;
      sonarr = 274;
      sonarr-anime = 273;
    };
    gids = {
      autobrr = 188;
      cross-seed = 183;
      jellyfin = 146;
      seerr = 250;
      media = 169;
      prowlarr = 287;
      recyclarr = 269;
    };
  };
}
