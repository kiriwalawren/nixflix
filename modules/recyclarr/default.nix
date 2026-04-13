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

        - 4k creates a profile named "[SQP] SQP-1 (2160p)"
        - 1080p creates a profile named "[SQP] SQP-1 (1080p)"

        If you want Seerr to use these, you'll have to configure them manually.

        Complex configurations can be manually applied using `nixflix.recyclarr.config.radarr.radarr`.
        If you do, you need to set
        `nixflix.recyclarr.config.radarr.radarr.quality_profiles = mkForce [];`.
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

        - 4k creates a quality profile named "WEB-2160p (Alternative)"
        - 1080p creates a quality profile named "WEB-1080p (Alternative)"

        If you want Seerr to use these, you'll have to configure them manually.

        Complex configurations can be manually applied using `nixflix.recyclarr.config.sonarr.sonarr`.
        If you do, you need to set
        `nixflix.recyclarr.config.sonarr.sonarr.quality_profiles = mkForce [];`.
      '';
    };

    cleanupUnmanagedProfiles = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to automatically remove quality profiles from Sonarr and Radarr
          that are are unmanaged.
        '';
      };

      managedProfiles = mkOption {
        type = types.listOf types.str;
        default =
          optional (cfg.radarrQuality == "4K") "[SQP] SQP-1 (2160p)"
          ++ optional (cfg.radarrQuality == "1080p") "[SQP] SQP-1 (1080p)"
          ++ optional (cfg.sonarrQuality == "4K") "WEB-2160p (Alternative)"
          ++ optional (cfg.sonarrQuality == "1080p") "WEB-1080p (Alternative)"
          ++ optional config.nixflix.sonarr-anime.enable "[Anime] Remux-1080p";
        defaultText = literalExpression ''
          optional (cfg.radarrQuality == "4K") "[SQP] SQP-1 (2160p)"
          ++ optional (cfg.radarrQuality == "1080p") "[SQP] SQP-1 (1080p)"
          ++ optional (cfg.sonarrQuality == "4K") "WEB-2160p (Alternative)"
          ++ optional (cfg.sonarrQuality == "1080p") "WEB-1080p (Alternative)"
          ++ optional config.nixflix.sonarr-anime.enable "[Anime] Remux-1080p";
        '';
        example = [ "My Custom Profile" ];
        description = ''
          List of profiles to keep.

          This list must be manually maintained if you change
          the default Recyclarr configuration.
        '';
      };
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions =
      let
        cfg' = cfg.config;
        instances = optionals (cfg' != null) (
          concatMap (svc: mapAttrsToList (name: inst: { inherit svc name inst; }) (cfg'.${svc} or { })) [
            "sonarr"
            "radarr"
          ]
        );
        set = v: v != null;
        xor = a: b: set a != set b;
      in
      concatMap (
        {
          svc,
          name,
          inst,
        }:
        let
          p = "nixflix.recyclarr.config.${svc}.${name}";
        in
        map (qp: {
          assertion = set (qp.name or null) || set (qp.trash_id or null);
          message = "${p}.quality_profiles: entry must set at least one of `name` or `trash_id`";
        }) (inst.quality_profiles or [ ])
        ++ map (inc: {
          assertion = xor (inc.template or null) (inc.config or null);
          message = "${p}.include: entry must set exactly one of `template` or `config`";
        }) (inst.include or [ ])
        ++ concatMap (
          cf:
          map (ref: {
            assertion = xor (ref.name or null) (ref.trash_id or null);
            message = "${p}.custom_formats.assign_scores_to: entry must set exactly one of `name` or `trash_id`";
          }) (cf.assign_scores_to or [ ])
        ) (inst.custom_formats or [ ])
        ++ concatMap (
          g:
          [
            {
              assertion = !((g.select_all or false) && set (g.select or null));
              message = "${p}.custom_format_groups.add: `select_all` and `select` are mutually exclusive";
            }
          ]
          ++ map (ref: {
            assertion = xor (ref.name or null) (ref.trash_id or null);
            message = "${p}.custom_format_groups.add.assign_scores_to: entry must set exactly one of `name` or `trash_id`";
          }) (g.assign_scores_to or [ ])
        ) ((inst.custom_format_groups or { }).add or [ ])
      ) instances;

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
        ++ optionals config.nixflix.radarr.enable [
          "radarr.service"
          "radarr-config.service"
        ]
        ++ optionals config.nixflix.sonarr.enable [
          "sonarr.service"
          "sonarr-config.service"
        ]
        ++ optionals config.nixflix.sonarr-anime.enable [
          "sonarr-anime.service"
          "sonarr-anime-config.service"
        ];
        requires =
          optionals config.nixflix.radarr.enable [
            "radarr.service"
            "radarr-config.service"
          ]
          ++ optionals config.nixflix.sonarr.enable [
            "sonarr.service"
            "sonarr-config.service"
          ]
          ++ optionals config.nixflix.sonarr-anime.enable [
            "sonarr-anime.service"
            "sonarr-anime-config.service"
          ];
        wants = [ "network-online.target" ];
        wantedBy = mkForce [ "multi-user.target" ];
      };
    };
  };
}
