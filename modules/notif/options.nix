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
          description = ''
            For more notification types, or if you have more than one instance of a specific type.
            Follows the same general schema as the other options. `implementationName` and `services` are required fields.
            Any field may be set to `{ _secret = /path/to/file; }` to read its value from a file at runtime.

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

      Unlike Downloadarr, not every notification type applies to every Starr service. Each notification type
      declares a `services` list controlling which Starr services it gets configured on.

      Each notification type exposes the fields of its Starr schema as typed options. Fields and triggers that
      every applicable Starr service supports are set on the type itself; ones that only some services support
      are set in that service's block (for example `nixflix.notif.gotify.sonarr.includeSeriesPoster`).

      Every service block (`sonarr`, `sonarr-anime`, `radarr` and `lidarr`) can also override any field or
      trigger set on the type itself, for that service only. A value set in the service block takes precedence
      over the type-level value; leaving it `null` uses the type-level value. For example, this posts Sonarr Anime
      notifications to a different Discord channel:

      ```nix
      nixflix.notif.discord = {
        webHookUrl = { _secret = "/run/secrets/discord-webhook"; };
        sonarr-anime.webHookUrl = { _secret = "/run/secrets/discord-anime-webhook"; };
      };
      ```

      `sonarr-anime` has its own block, separate from `sonarr`, so settings in `sonarr` do not apply to it.

      Anything not modeled here can be configured through `extraNotifications`.
    '';
  };
}
