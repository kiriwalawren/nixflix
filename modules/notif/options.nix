{ config, lib, ... }:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  notifLib = import ./lib.nix { inherit lib secrets; };

  importType =
    name:
    import (./types + "/${name}.nix") {
      inherit
        config
        lib
        secrets
        notifLib
        ;
    };

  notificationTypes = [
    "jellyfin"
    "subsonic"
    "ntfy"
    "apprise"
    "customScript"
    "discord"
    "email"
    "gotify"
    "join"
    "kodi"
    "mailgun"
    "notifiarr"
    "plex"
    "prowl"
    "pushbullet"
    "pushcut"
    "pushover"
    "pushsafer"
    "sendgrid"
    "signal"
    "simplepush"
    "slack"
    "synologyIndexer"
    "telegram"
    "twitter"
    "webhook"
    "webpush"
  ];
in
{
  options.nixflix.notif = mkOption {
    type = types.submodule {
      options = genAttrs notificationTypes importType // {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable Notif.";
        };

        extraNotifications = mkOption {
          type = types.listOf (types.attrsOf types.anything);
          default = [ ];
          example = literalExpression ''
            [
              {
                name = "Discord (anime)";
                implementationName = "Discord";
                webHookUrl = { _secret = "/run/secrets/discord-anime-webhook"; };
                username = "Anime";
                tags = [ "anime" ];
                sonarr-anime = {
                  enable = true;
                  onGrab = true;
                  onDownload = true;
                  onUpgrade = true;
                };
                radarr = {
                  enable = true;
                  onDownload = true;
                  username = "Anime Movies";
                };
              }
            ]
          '';
          description = ''
            For more notification types, or if you have more than one instance of a specific type.
            Each entry follows the same schema as the typed connectors, but is not type checked:

            - `name` (required): name of the connection in Starr. It must be unique, because it is how nixflix
              finds the connection to update, and connections whose name is not configured are deleted.
            - `implementationName` (required): the Starr notification type, for example `Discord`.
            - `sonarr`, `sonarr-anime`, `radarr` and `lidarr`: one block per Starr service. An entry is only
              configured on the services whose block sets `enable = true`. Triggers are booleans in the block (for
              example `radarr.onGrab = true`), and any trigger not set to `true` is turned off. Any other field set
              in a block overrides the top-level value for that service only.
            - `tags`: Starr tag labels that restrict the connection to tagged items. Missing tags are created.
            - `dependencies`: systemd services to start before the entry is configured.
            - Any other attribute is a field of the Starr schema for `implementationName` (for example
              `webHookUrl`), or a top-level setting of the connection such as `includeHealthWarnings`.

            Any field may be set to `{ _secret = /path/to/file; }` to read its value from a file at runtime.
            Seerr cannot be targeted from here; use the `seerr` block of a typed connector instead.

            A list of implementation names can be acquired with:

            ```sh
            curl -s -H "X-Api-Key: $(sudo cat </path/to/sonarr/api_key>)" "http://127.0.0.1:8989/api/v3/notification/schema" | jq '.[].implementationName'
            ```

            You can run the following command to get the field names for a particular `implementationName`:

            ```sh
            curl -s -H "X-Api-Key: $(sudo cat </path/to/sonarr/api_key>)" "http://127.0.0.1:8989/api/v3/notification/schema" | jq '.[] | select(.implementationName=="<implementationName>") | .fields'
            ```
          '';
        };
      };
    };
    default = { };
    description = ''
      Notif is a service that is responsible for configuring Starr services with "Connect" notifications.
      When you enable the service for a target that it applies to, Notif integrates it automatically with each applicable Starr service.

      Unlike Downloadarr, not every notification type applies to every Starr service. Each notification type has
      a block for each service it supports (`sonarr`, `sonarr-anime`, `radarr`, `lidarr` and, where Seerr supports
      it, `seerr`), and is configured only on the services whose block is enabled.

      Each notification type exposes the fields of its Starr schema as typed options. Fields that every
      applicable Starr service supports are set on the type itself; ones that only some services support are set
      in that service's block (for example `nixflix.notif.gotify.sonarr.includeSeriesPoster`). Triggers are always
      set in the service block (for example `nixflix.notif.gotify.sonarr.onGrab`), because not every trigger
      applies to every service.

      Every service block (`sonarr`, `sonarr-anime`, `radarr` and `lidarr`) can also override any field set on
      the type itself, for that service only. A value set in the service block takes precedence
      over the type-level value; leaving it `null` uses the type-level value. For example, this posts Sonarr Anime
      notifications to a different Discord channel:

      ```nix
      nixflix.notif.discord = {
        webHookUrl = { _secret = "/run/secrets/discord-webhook"; };
        sonarr.enable = true;
        sonarr-anime = {
          enable = true;
          webHookUrl = { _secret = "/run/secrets/discord-anime-webhook"; };
        };
      };
      ```

      `sonarr-anime` has its own block, separate from `sonarr`, so settings in `sonarr` do not apply to it.

      Each service block has an `enable` option, and there is no connector-level `enable`: a connector is used
      only by the services whose block is enabled (for example `nixflix.notif.discord.radarr.enable = true`).
      Service blocks are opt-in and default to `false`, so services added to nixflix later stay off until you turn
      them on. The exceptions are `jellyfin` and `subsonic`, whose blocks default to whether Jellyfin or Navidrome
      is enabled so their libraries keep refreshing automatically (`jellyfin.lidarr` only when a Jellyfin `Music`
      library exists).

      Seerr is also a target, through the `seerr` block of `discord`, `email`, `gotify`, `ntfy`, `pushbullet`,
      `pushover`, `slack`, `telegram`, `webhook` and `webpush` (Seerr only), when `seerr.enable` is set (for
      example `nixflix.notif.discord.seerr.enable = true`). The `seerr` block uses the same
      option names as the type (for example `nixflix.notif.discord.seerr.username`), but only offers the fields
      Seerr supports, plus Seerr-only options and one boolean per Seerr notification type (for example
      `nixflix.notif.discord.seerr.onMediaPending`, all `true` by default; `email` and `webpush` have none
      because Seerr sends those per user). Seerr has a single configuration per agent, so `extraNotifications`
      cannot target it. When `nixflix.seerr` is enabled, any Seerr agent that no enabled `seerr` block targets is
      disabled, keeping its other settings.

      Anything not modeled here can be configured through `extraNotifications`.
    '';
  };
}
