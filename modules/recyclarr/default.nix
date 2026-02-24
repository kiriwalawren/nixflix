{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.nixflix.recyclarr;

  removeNulls =
    v:
    if builtins.isAttrs v then
      builtins.foldl' (
        acc: name:
        let
          val = v.${name};
        in
        if name == "_module" || val == null then acc else acc // { ${name} = removeNulls val; }
      ) { } (builtins.attrNames v)
    else if builtins.isList v then
      map removeNulls v
    else
      v;
in
{
  imports = [
    ./cleanup-profiles.nix
    ./config-option.nix
    ./radarr.nix
    ./sonarr-anime.nix
    ./sonarr.nix
  ];

  options.nixflix.recyclarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable Recyclarr for automated TRaSH guide syncing.

        Default configurations select profiles that prioritize acquisition over quality.
        Lower quality hits that meet TRaSH standards will be accepted and grabbed.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "recyclarr";
      description = "User under which Recyclarr runs.";
    };

    group = mkOption {
      type = types.str;
      default = "recyclarr";
      description = "Group under which Recyclarr runs.";
    };

    radarrQuality = mkOption {
      type = types.enum [
        "4K"
        "1080p"
      ];
      default = "1080p";
      example = "4K";
      description = ''
        Allows for easy recyclarr quality profile configuration for the radarr instance.

        This option selects profiles that prioritize acquisition over quality.
        Lower quality hits that meet TRaSH standards will be accepted and grabbed.

        - 4k creates a profile named "SQP-1 (2160p)"
        - 1080p creates a profile named "SQP-1 (1080p)"

        If you want Jellyseerr to use these, you'll have to configure them manually.

        Complex configurations can be manually applied using `nixflix.recyclarr.config.radarr.radarr`.
        If you do, you need to set `nixflix.recyclarr.config.radarr.radarr.include = mkForce [];`.
      '';
    };

    sonarrQuality = mkOption {
      type = types.enum [
        "4K"
        "1080p"
      ];
      default = "1080p";
      example = "4K";
      description = ''
        Allows for easy recyclarr quality profile configuration for the sonarr instance.
        Does not effect `Sonarr Anime`.

        This option selects profiles that prioritize acquisition over quality.
        Lower quality hits that meet TRaSH standards will be accepted and grabbed.

        - 4k creates a quality profile named "WEB-2160p"
        - 1080p creates a quality profile named "WEB-1080p"

        If you want Jellyseerr to use these, you'll have to configure them manually.

        Complex configurations can be manually applied using `nixflix.recyclarr.config.sonarr.sonarr`.
        If you do, you need to set `nixflix.recyclarr.config.sonarr.sonarr.include = mkForce [];`.
      '';
    };

    cleanupUnmanagedProfiles = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to automatically remove quality profiles from Sonarr and Radarr
        that are not managed by Recyclarr.

        Only removes profiles from instances matching nixflix.sonarr and nixflix.radarr
        base URLs, and only when `quality_profiles` is defined in the Recyclarr configuration.

        Any series/movies using unmanaged profiles will be reassigned to the first
        managed profile before deletion.

        !!! warning

            This is a dangerous option that will remove profiles configured using the `include` option (if you also
            define `quality_profiles`) because profiles created by `include` cannot be known to Nix at build time.
      '';
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    users.users.${cfg.user} = optionalAttrs (config.nixflix.globals.uids ? ${cfg.user}) {
      uid = mkForce config.nixflix.globals.uids.${cfg.user};
    };

    users.groups.${cfg.group} = optionalAttrs (config.nixflix.globals.gids ? ${cfg.group}) {
      gid = mkForce config.nixflix.globals.gids.${cfg.group};
    };

    services.recyclarr = {
      enable = true;
      inherit (cfg) user group;
      configuration = removeNulls cfg.config;
      schedule = "daily";
    };

    systemd.services = {
      recyclarr = {
        after = [
          "network-online.target"
        ]
        ++ optional config.nixflix.radarr.enable "radarr-config.service"
        ++ optional config.nixflix.sonarr.enable "sonarr-config.service"
        ++ optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service";
        requires =
          optional config.nixflix.radarr.enable "radarr-config.service"
          ++ optional config.nixflix.sonarr.enable "sonarr-config.service"
          ++ optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service";
        wants = [ "network-online.target" ];
        wantedBy = mkForce [ "multi-user.target" ];
      };
    };
  };
}
