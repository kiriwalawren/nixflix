{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  getFirstAdmin = import ../../lib/getFirstAdmin.nix { inherit lib; };

  navidromeAdmin =
    (getFirstAdmin {
      inherit (config.nixflix.navidrome) users;
      isAdmin = user: user.isAdmin;
    }).user;

  mkNotificationType =
    {
      implementationName,
      enable ? { },
      dependencies ? { },
      services ? { },
      extraOptions ? { },
    }:
    types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption (
          {
            type = types.bool;
            default = false;
            description = "Whether or not this notification is enabled.";
          }
          // enable
        );

        dependencies = mkOption (
          {
            type = types.listOf types.str;
            default = [ ];
            description = "systemd services that this integration depends on";
          }
          // dependencies
        );

        services = mkOption (
          {
            type = types.listOf types.str;
            default = [ ];
            description = "Which Starr services to configure this notification on.";
          }
          // services
        );

        name = mkOption {
          type = types.str;
          default = implementationName;
          description = "User-defined name for the notification instance.";
        };

        implementationName = mkOption {
          type = types.str;
          readOnly = true;
          default = implementationName;
          description = "Type of notification to configure (matches schema implementationName).";
        };
      }
      // extraOptions;
    };

  jellyfinType = mkNotificationType {
    implementationName = "Emby / Jellyfin";

    enable = {
      default = config.nixflix.jellyfin.enable;
      defaultText = literalExpression "config.nixflix.jellyfin.enable";
    };

    dependencies.default = [ "jellyfin.service" ];

    services = {
      default = optionals config.nixflix.jellyfin.enable (
        [
          "sonarr"
          "sonarr-anime"
          "radarr"
        ]
        ++ optional (config.nixflix.jellyfin.libraries.Music or null != null) "lidarr"
      );
      defaultText = literalExpression ''
        optionals config.nixflix.jellyfin.enable (
          [ "sonarr" "sonarr-anime" "radarr" ]
          ++ optional (config.nixflix.jellyfin.libraries.Music or null != null) "lidarr"
        )
      '';
    };

    extraOptions = {
      host = mkOption {
        type = types.str;
        description = "Host of the Jellyfin server.";
        default = config.nixflix.jellyfin.connectionAddress;
        defaultText = literalExpression "config.nixflix.jellyfin.connectionAddress";
      };

      port = mkOption {
        type = types.port;
        description = "Port of the Jellyfin server.";
        default = config.nixflix.jellyfin.network.internalHttpPort;
        defaultText = literalExpression "config.nixflix.jellyfin.network.internalHttpPort";
      };

      apiKey = secrets.mkSecretOption {
        description = "API key for Jellyfin.";
        default = config.nixflix.jellyfin.apiKey;
        defaultText = literalExpression "config.nixflix.jellyfin.apiKey";
        nullable = true;
      };
    };
  };

  subsonicType = mkNotificationType {
    implementationName = "Subsonic";

    enable = {
      default = config.nixflix.navidrome.enable;
      defaultText = literalExpression "config.nixflix.navidrome.enable";
    };

    dependencies.default = [ "navidrome.service" ];

    services.default = [ "lidarr" ];

    extraOptions = {
      host = mkOption {
        type = types.str;
        description = "Host of the Navidrome (Subsonic) server.";
        default = config.nixflix.navidrome.connectionAddress;
        defaultText = literalExpression "config.nixflix.navidrome.connectionAddress";
      };

      port = mkOption {
        type = types.port;
        description = "Port of the Navidrome (Subsonic) server.";
        default = config.nixflix.navidrome.settings.Port;
        defaultText = literalExpression "config.nixflix.navidrome.settings.Port";
      };

      username = secrets.mkSecretOption {
        description = "Username for the Navidrome (Subsonic) server.";
        default = navidromeAdmin.userName or null;
        defaultText = literalExpression "(getFirstAdmin { inherit (config.nixflix.navidrome) users; isAdmin = user: user.isAdmin; }).user.userName";
        nullable = true;
      };

      password = secrets.mkSecretOption {
        description = "Password for the Navidrome (Subsonic) server.";
        default = navidromeAdmin.password or null;
        defaultText = literalExpression "(getFirstAdmin { inherit (config.nixflix.navidrome) users; isAdmin = user: user.isAdmin; }).user.password";
        nullable = true;
      };
    };
  };

  ntfyType = mkNotificationType {
    implementationName = "ntfy.sh";

    services.default = [
      "sonarr"
      "sonarr-anime"
      "radarr"
      "lidarr"
    ];

    extraOptions = {
      serverUrl = mkOption {
        type = types.str;
        default = "https://ntfy.sh";
        description = "ntfy server URL.";
      };

      topics = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Topics to publish notifications to.";
      };

      accessToken = secrets.mkSecretOption {
        description = "Access token for the ntfy server.";
        nullable = true;
      };

      username = secrets.mkSecretOption {
        description = "Username for the ntfy server.";
        nullable = true;
      };

      password = secrets.mkSecretOption {
        description = "Password for the ntfy server.";
        nullable = true;
      };

      priority = mkOption {
        type = types.ints.between 1 5;
        default = 3;
        description = "Priority of the notification.";
      };

      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Tags/emojis to include on the notification.";
      };

      clickUrl = mkOption {
        type = types.str;
        default = "";
        description = "URL to open when the notification is clicked.";
      };
    };
  };
in
{
  options.nixflix.notif = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable Notif.";
        };

        jellyfin = mkOption {
          type = jellyfinType;
          default = { };
          description = "Emby/Jellyfin notification definition for Starr services.";
        };

        subsonic = mkOption {
          type = subsonicType;
          default = { };
          description = "Subsonic notification definition for Starr services.";
        };

        ntfy = mkOption {
          type = ntfyType;
          default = { };
          description = "ntfy notification definition for Starr services.";
        };

        extraNotifications = mkOption {
          type = types.listOf (types.attrsOf types.anything);
          default = [ ];
          description = ''
            For more notification types, or if you have more than one instance of a specific type.
            Follows the same general schema as the other options. `implementationName` and `services` are required fields.

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

      Each module is currently only a subset of the options available. You can add more options represented
      in the UI if you know their keys, or add an entirely new type via `extraNotifications`.
    '';
  };
}
