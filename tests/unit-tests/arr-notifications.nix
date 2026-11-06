{
  pkgs,
  lib,
  evalConfig,
  check,
  ...
}:
{
  notif-service-scoping =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
            };

            navidrome.enable = true;
            navidrome.users.admin = {
              userName = "admin";
              isAdmin = true;
              password = "testpassword";
            };

            sonarr = {
              enable = true;
              config = {
                hostConfig.port = 8989;
                apiKey._secret = "/run/secrets/sonarr-api";
              };
            };

            radarr = {
              enable = true;
              config = {
                hostConfig.port = 7878;
                apiKey._secret = "/run/secrets/radarr-api";
              };
            };

            lidarr = {
              enable = true;
              config = {
                hostConfig.port = 8686;
                apiKey._secret = "/run/secrets/lidarr-api";
              };
            };
          };
        }
      ];
      sonarrNotifications = config.config.systemd.services."sonarr-notifications";
      radarrNotifications = config.config.systemd.services."radarr-notifications";
      lidarrNotifications = config.config.systemd.services."lidarr-notifications";
    in
    pkgs.runCommand "unit-test-notif-service-scoping" { } ''
      ${check "sonarr-notifications ExecStartPre uses connectionAddress" (
        lib.hasInfix "127.0.0.1" sonarrNotifications.serviceConfig.ExecStartPre
      )}
      ${check "sonarr-notifications ExecStartPre does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" sonarrNotifications.serviceConfig.ExecStartPre
      )}
      ${check "radarr-notifications script uses connectionAddress" (
        lib.hasInfix "127.0.0.1" radarrNotifications.script
      )}
      ${check "sonarr-notifications is configured for Emby/Jellyfin" (
        lib.hasInfix "Emby / Jellyfin" sonarrNotifications.script
      )}
      ${check "sonarr-notifications is NOT configured for Subsonic (Lidarr-only)" (
        !lib.hasInfix "Subsonic" sonarrNotifications.script
      )}
      ${check "lidarr-notifications is configured for Emby/Jellyfin" (
        lib.hasInfix "Emby / Jellyfin" lidarrNotifications.script
      )}
      ${check "lidarr-notifications is configured for Subsonic" (
        lib.hasInfix "Subsonic" lidarrNotifications.script
      )}
      echo 'PASS: notif-service-scoping' > $out
    '';

  notif-triggers =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
            };

            sonarr = {
              enable = true;
              config = {
                hostConfig.port = 8989;
                apiKey._secret = "/run/secrets/sonarr-api";
              };
            };

            radarr = {
              enable = true;
              config = {
                hostConfig.port = 7878;
                apiKey._secret = "/run/secrets/radarr-api";
              };
            };

            notif.jellyfin.triggers.sonarr = [
              "onDownload"
              "onHealthIssue"
            ];

            notif.jellyfin.includeHealthWarnings = true;
          };
        }
      ];
      sonarrNotifications = config.config.systemd.services."sonarr-notifications";
      radarrNotifications = config.config.systemd.services."radarr-notifications";
    in
    pkgs.runCommand "unit-test-notif-triggers" { } ''
      ${check "sonarr-notifications applies the overridden trigger set" (
        lib.hasInfix ''["onDownload","onHealthIssue"]'' sonarrNotifications.script
      )}
      ${check "radarr-notifications still uses the jellyfin default trigger set" (
        lib.hasInfix ''["onGrab","onDownload","onUpgrade","onRename","onMovieDelete","onMovieFileDelete","onMovieFileDeleteForUpgrade","onApplicationUpdate"]'' radarrNotifications.script
      )}
      ${check "sonarr-notifications applies the freeform includeHealthWarnings override" (
        lib.hasInfix ''"includeHealthWarnings":true'' sonarrNotifications.script
      )}
      ${check "apply_field_overrides merges top-level overrides (name, enable, freeform properties)" (
        lib.hasInfix ". + \$overrides" sonarrNotifications.script
      )}
      ${check "notification overrides do not include the nested triggers attrset" (
        !lib.hasInfix "\"triggers\":" sonarrNotifications.script
      )}
      echo 'PASS: notif-triggers' > $out
    '';
}
