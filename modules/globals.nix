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
      jellyfin = 146;
      autobrr = 188;
      bazarr = 232;
      lidarr = 306;
      prowlarr = 293;
      jellyseerr = 262;
      sonarr = 274;
      sonarr-anime = 273;
      radarr = 275;
      recyclarr = 269;
      sabnzbd = 38;
      transmission = 70;
      cross-seed = 183;
    };
    gids = {
      autobrr = 188;
      cross-seed = 183;
      jellyfin = 146;
      jellyseerr = 250;
      media = 169;
      prowlarr = 287;
      recyclarr = 269;
    };
  };
}
