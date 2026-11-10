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
      ${check "sonarr-notifications applies the includeHealthWarnings option" (
        lib.hasInfix ''"includeHealthWarnings":true'' sonarrNotifications.script
      )}
      ${check "apply_field_overrides merges top-level overrides (name, enable, includeHealthWarnings)" (
        lib.hasInfix ". + (\$overrides" sonarrNotifications.script
      )}
      ${check "notification overrides do not include the nested triggers attrset" (
        !lib.hasInfix "\"triggers\":" sonarrNotifications.script
      )}
      echo 'PASS: notif-triggers' > $out
    '';

  notif-any-field-secret =
    let
      tokenFile = "/run/secrets/notif-token";
      ntfyPasswordFile = "/run/secrets/ntfy-password";
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            sonarr = {
              enable = true;
              config = {
                hostConfig.port = 8989;
                apiKey._secret = "/run/secrets/sonarr-api";
              };
            };

            notif = {
              ntfy = {
                enable = true;
                topics = [ "media" ];
                password._secret = ntfyPasswordFile;
              };
              extraNotifications = [
                {
                  enable = true;
                  name = "Gotify";
                  implementationName = "Gotify";
                  services = [ "sonarr" ];
                  dependencies = [ ];
                  server = "https://gotify.example";
                  appToken._secret = tokenFile;
                }
              ];
            };
          };
        }
      ];
      script = config.config.systemd.services."sonarr-notifications".script;
    in
    pkgs.runCommand "unit-test-notif-any-field-secret" { } ''
      ${check "script reads the extra notification secret via --rawfile" (
        lib.hasInfix "--rawfile" script && lib.hasInfix tokenFile script
      )}
      ${check "script reads the ntfy password via --rawfile" (lib.hasInfix ntfyPasswordFile script)}
      ${check "no _secret refs leak into the override JSON" (!lib.hasInfix "_secret" script)}
      echo 'PASS: notif-any-field-secret' > $out
    '';

  notif-all-connector-types =
    let
      connectors = {
        apprise = {
          impl = "Apprise";
          secret = "authPassword";
        };
        customScript = {
          impl = "Custom Script";
          secret = null;
        };
        discord = {
          impl = "Discord";
          secret = "webHookUrl";
        };
        email = {
          impl = "Email";
          secret = "password";
        };
        gotify = {
          impl = "Gotify";
          secret = "appToken";
        };
        join = {
          impl = "Join";
          secret = "apiKey";
        };
        kodi = {
          impl = "Kodi";
          secret = "password";
        };
        mailgun = {
          impl = "Mailgun";
          secret = "apiKey";
        };
        notifiarr = {
          impl = "Notifiarr";
          secret = "apiKey";
        };
        plex = {
          impl = "Plex Media Server";
          secret = "authToken";
        };
        prowl = {
          impl = "Prowl";
          secret = "apiKey";
        };
        pushbullet = {
          impl = "Pushbullet";
          secret = "apiKey";
        };
        pushcut = {
          impl = "Pushcut";
          secret = "apiKey";
        };
        pushover = {
          impl = "Pushover";
          secret = "apiKey";
        };
        pushsafer = {
          impl = "Pushsafer";
          secret = "apiKey";
        };
        sendgrid = {
          impl = "SendGrid";
          secret = "apiKey";
        };
        signal = {
          impl = "Signal";
          secret = "authPassword";
        };
        simplepush = {
          impl = "Simplepush";
          secret = "key";
        };
        slack = {
          impl = "Slack";
          secret = "webHookUrl";
        };
        synologyIndexer = {
          impl = "Synology Indexer";
          secret = null;
        };
        telegram = {
          impl = "Telegram";
          secret = "botToken";
        };
        twitter = {
          impl = "Twitter";
          secret = "consumerSecret";
        };
        webhook = {
          impl = "Webhook";
          secret = "password";
        };
      };
      secretPath = name: "/run/secrets/notif-${name}";
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            lidarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/lidarr-api";
            };
            notif = lib.mapAttrs (
              name: c:
              {
                enable = true;
              }
              // lib.optionalAttrs (c.secret != null) { ${c.secret}._secret = secretPath name; }
            ) connectors;
          };
        }
      ];
      scripts = lib.genAttrs [ "sonarr" "radarr" "lidarr" ] (
        s: config.config.systemd.services."${s}-notifications".script
      );
      expectedOn = name: service: name != "pushsafer" || service == "radarr";
      checks = lib.concatLists (
        lib.mapAttrsToList (
          name: c:
          map (
            service:
            let
              script = scripts.${service};
              present = lib.hasInfix "Processing notification: ${c.impl}" script;
            in
            ''
              ${check "${name} configured on ${service} only when the schema has it" (
                present == expectedOn name service
              )}
              ${check "${name} secret is read by path on ${service}" (
                c.secret == null || !(expectedOn name service) || lib.hasInfix (secretPath name) script
              )}
            ''
          ) (lib.attrNames scripts)
        ) connectors
      );
    in
    pkgs.runCommand "unit-test-notif-all-connector-types" { } ''
      ${lib.concatStrings checks}
      ${check "no _secret refs leak into any script" (
        lib.all (script: !lib.hasInfix "_secret" script) (lib.attrValues scripts)
      )}
      echo 'PASS: notif-all-connector-types' > $out
    '';

  notif-connector-trigger-validation =
    let
      evaluates =
        notifConfig:
        (builtins.tryEval (
          builtins.deepSeq (lib.mapAttrs (
            name: _:
            (evalConfig [
              {
                nixflix = {
                  enable = true;
                  notif = notifConfig;
                };
              }
            ]).config.nixflix.notif.${name}
          ) notifConfig) true
        )).success;
      notifLib = import ../../modules/notif/lib.nix {
        inherit lib;
        secrets = import ../../lib/secrets { inherit lib; };
      };
      connectorEvaluates =
        perService:
        (builtins.tryEval (
          builtins.deepSeq
            (lib.evalModules {
              modules = [
                {
                  options.connector = notifLib.mkConnectorOption {
                    implementationName = "Test";
                    description = "Test connector.";
                    inherit perService;
                  };
                }
              ];
            }).config.connector._supportedTriggers
            true
        )).success;
      supported = (evalConfig [ { nixflix.enable = true; } ]).config.nixflix.notif;
    in
    pkgs.runCommand "unit-test-notif-connector-trigger-validation" { } ''
      ${check "a well-formed perService spec evaluates" (connectorEvaluates {
        sonarr.unsupportedTriggers = [ "onRename" ];
      })}
      ${check "a perService spec given as a bare list is rejected" (
        !connectorEvaluates { radarr = [ "onRename" ]; }
      )}
      ${check "an unknown perService key is rejected" (
        !connectorEvaluates { radarr.unsuportedTriggers = [ "onRename" ]; }
      )}
      ${check "an unsupported trigger that the service lacks is rejected" (
        !connectorEvaluates { radarr.unsupportedTriggers = [ "onSeriesAdd" ]; }
      )}
      ${check "kodi supports onManualInteractionRequired on sonarr" (
        lib.elem "onManualInteractionRequired" supported.kodi._supportedTriggers.sonarr
      )}
      ${check "pushsafer does not support onRename on radarr" (
        !lib.elem "onRename" supported.pushsafer._supportedTriggers.radarr
      )}
      ${check "plex accepts a supported sonarr-only trigger" (evaluates {
        plex.sonarr.onDownload = true;
      })}
      ${check "plex has no sonarr onGrab, which its sonarr schema does not support" (
        !evaluates { plex.sonarr.onGrab = true; }
      )}
      ${check "a shared trigger is not accepted in a service block" (
        !evaluates { gotify.radarr.onGrab = true; }
      )}
      ${check "an undeclared top-level name is rejected" (!evaluates { gotify.bogusField = true; })}
      ${check "a service block that the schema lacks is rejected" (
        !evaluates { pushsafer.sonarr.onDownload = true; }
      )}
      ${check "the legacy list form still evaluates on jellyfin" (evaluates {
        jellyfin = {
          apiKey = "test-jellyfin-key";
          triggers.sonarr = [ "onDownload" ];
        };
      })}
      echo 'PASS: notif-connector-trigger-validation' > $out
    '';

  notif-field-names =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            notif = {
              notifiarr = {
                enable = true;
                apiKey = "plain-notifiarr-key";
              };
              ntfy = {
                enable = true;
                topics = [ "media" ];
                username = "legacy-user";
              };
            };
          };
        }
      ];
      script = config.config.systemd.services."radarr-notifications".script;
    in
    pkgs.runCommand "unit-test-notif-field-names" { } ''
      ${check "notifiarr sets the Sonarr field name apiKey" (
        lib.hasInfix ''"apiKey":"plain-notifiarr-key"'' script
      )}
      ${check "notifiarr sets the Radarr/Lidarr field name aPIKey" (
        lib.hasInfix ''"aPIKey":"plain-notifiarr-key"'' script
      )}
      ${check "legacy ntfy username is sent as the schema field userName" (
        lib.hasInfix ''"userName":"legacy-user"'' script
      )}
      ${check "field-named overrides are not merged into the top level" (
        lib.hasInfix "select(.key as $k | $fieldNames | index($k) == null)" script
      )}
      echo 'PASS: notif-field-names' > $out
    '';

  notif-webhook-headers =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            notif.webhook = {
              enable = true;
              url = "https://hooks.example/notify";
              headers = [
                {
                  key = "Authorization";
                  value._secret = "/run/secrets/webhook-auth";
                }
                {
                  key = "X-Plain";
                  value = "plain-value";
                }
              ];
            };
          };
        }
      ];
      script = config.config.systemd.services."sonarr-notifications".script;
    in
    pkgs.runCommand "unit-test-notif-webhook-headers" { } ''
      ${check "headers are sent as a key/value list with the secret value stripped" (
        lib.hasInfix ''"headers":[{"key":"Authorization"},{"key":"X-Plain","value":"plain-value"}]'' script
      )}
      ${check "secret header value is read from its file" (
        lib.hasInfix "/run/secrets/webhook-auth" script
      )}
      ${check "secret header value is assigned into the first header" (
        lib.hasInfix ''.["headers"][0]["value"] = ($nixflixSecret0Content'' script
      )}
      echo 'PASS: notif-webhook-headers' > $out
    '';

  notif-tags =
    let
      scriptFor =
        notif:
        (evalConfig [
          {
            nixflix = {
              enable = true;
              sonarr = {
                enable = true;
                config.apiKey._secret = "/run/secrets/sonarr-api";
              };
              inherit notif;
            };
          }
        ]).config.systemd.services."sonarr-notifications".script;
      gotify = scriptFor {
        gotify = {
          enable = true;
          tags = [
            "anime"
            "4k"
          ];
        };
      };
      ntfy = scriptFor {
        ntfy = {
          enable = true;
          topics = [ "media" ];
          ntfyTags = [ "warning" ];
          tags = [ "anime" ];
        };
      };
      apprise = scriptFor {
        apprise = {
          enable = true;
          appriseTags = [ "family" ];
        };
      };
      untagged = scriptFor { gotify.enable = true; };
      rejects =
        notif:
        !(builtins.tryEval (
          builtins.deepSeq
            (evalConfig [
              {
                nixflix = {
                  enable = true;
                  inherit notif;
                };
              }
            ]).config.nixflix.notif.gotify.tags
            true
        )).success;
    in
    pkgs.runCommand "unit-test-notif-tags" { } ''
      ${check "tags are fetched from the tag endpoint" (lib.hasInfix "$BASE_URL/tag" gotify)}
      ${check "each label is resolved to an id" (
        lib.hasInfix "resolve_tag_id anime" gotify && lib.hasInfix "resolve_tag_id 4k" gotify
      )}
      ${check "resolved ids replace the top-level tags" (lib.hasInfix ".tags = $tagIds" gotify)}
      ${check "Starr tags are not sent as a field override" (!lib.hasInfix ''"tags":'' gotify)}
      ${check "ntfy tags/emojis are sent as the schema field tags" (
        lib.hasInfix ''"tags":["warning"]'' ntfy
      )}
      ${check "ntfy Starr tags are resolved separately" (lib.hasInfix "resolve_tag_id anime" ntfy)}
      ${check "apprise tags are sent as the schema field tags" (
        lib.hasInfix ''"tags":["family"]'' apprise
      )}
      ${check "no tag lookups without tags" (!lib.hasInfix "Fetching tags" untagged)}
      ${check "uppercase labels are rejected" (rejects {
        gotify.tags = [ "Anime" ];
      })}
      echo 'PASS: notif-tags' > $out
    '';

  notif-boolean-triggers =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            sonarr-anime = {
              enable = true;
              config = {
                hostConfig.port = 8990;
                apiKey._secret = "/run/secrets/sonarr-anime-api";
              };
            };
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            lidarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/lidarr-api";
            };
            notif.gotify = {
              enable = true;
              onGrab = false;
              sonarr.onSeriesAdd = false;
              radarr.onHealthIssue = true;
            };
          };
        }
      ];
      script = s: config.config.systemd.services."${s}-notifications".script;
      sonarrTriggers = ''["onDownload","onUpgrade","onImportComplete","onSeriesDelete","onEpisodeFileDelete","onEpisodeFileDeleteForUpgrade","onApplicationUpdate","onManualInteractionRequired"]'';
    in
    pkgs.runCommand "unit-test-notif-boolean-triggers" { } ''
      ${check "sonarr gets UI defaults minus the shared onGrab and its own onSeriesAdd" (
        lib.hasInfix sonarrTriggers (script "sonarr")
      )}
      ${check "sonarr-anime uses the sonarr block" (lib.hasInfix sonarrTriggers (script "sonarr-anime"))}
      ${check "radarr enables its per-service onHealthIssue and drops the shared onGrab" (
        lib.hasInfix ''["onDownload","onUpgrade","onMovieAdded","onMovieDelete","onMovieFileDelete","onMovieFileDeleteForUpgrade","onHealthIssue","onApplicationUpdate","onManualInteractionRequired"]'' (
          script "radarr"
        )
      )}
      ${check "lidarr keeps the UI default onHealthIssue and drops the shared onGrab" (
        lib.hasInfix ''["onReleaseImport","onUpgrade","onArtistAdd","onArtistDelete","onHealthIssue","onDownloadFailure","onImportFailure","onApplicationUpdate"]'' (
          script "lidarr"
        )
      )}
      ${check "trigger booleans are not sent as overrides" (
        lib.all (s: !lib.hasInfix ''"onGrab":'' (script s) && !lib.hasInfix ''"onHealthIssue":'' (script s))
          [
            "sonarr"
            "radarr"
            "lidarr"
          ]
      )}
      echo 'PASS: notif-boolean-triggers' > $out
    '';

  notif-per-service-fields =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            lidarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/lidarr-api";
            };
            notif = {
              gotify = {
                enable = true;
                sonarr.includeSeriesPoster = true;
                radarr.metadataLinks = [ 0 ];
              };
              email = {
                enable = true;
                lidarr.requireEncryption = true;
              };
            };
          };
        }
      ];
      script = s: config.config.systemd.services."${s}-notifications".script;
      rejects =
        notifConfig:
        !(builtins.tryEval (
          builtins.deepSeq (lib.mapAttrs (
            name: _:
            (evalConfig [
              {
                nixflix = {
                  enable = true;
                  notif = notifConfig;
                };
              }
            ]).config.nixflix.notif.${name}
          ) notifConfig) true
        )).success;
    in
    pkgs.runCommand "unit-test-notif-per-service-fields" { } ''
      ${check "sonarr-only field is sent to sonarr" (
        lib.hasInfix ''"includeSeriesPoster":true'' (script "sonarr")
      )}
      ${check "sonarr-only field is not sent to radarr or lidarr" (
        !lib.hasInfix "includeSeriesPoster" (script "radarr")
        && !lib.hasInfix "includeSeriesPoster" (script "lidarr")
      )}
      ${check "radarr metadataLinks is sent to radarr only" (
        lib.hasInfix ''"metadataLinks":[0]'' (script "radarr")
        && !lib.hasInfix "metadataLinks" (script "sonarr")
      )}
      ${check "lidarr-only email field is sent to lidarr only" (
        lib.hasInfix ''"requireEncryption":true'' (script "lidarr")
        && !lib.hasInfix "requireEncryption" (script "sonarr")
      )}
      ${check "a field is rejected in the block of another service" (rejects {
        gotify.radarr.includeSeriesPoster = true;
      })}
      ${check "radarr metadataLinks rejects a sonarr-only value" (rejects {
        gotify.radarr.metadataLinks = [ 3 ];
      })}
      echo 'PASS: notif-per-service-fields' > $out
    '';

  notif-default-triggers-unchanged =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            jellyfin = {
              enable = true;
              apiKey = "test-jellyfin-key";
            };
            navidrome = {
              enable = true;
              users.admin = {
                userName = "admin";
                isAdmin = true;
                password = "testpassword";
              };
            };
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            lidarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/lidarr-api";
            };
            notif = {
              jellyfin.services = [
                "sonarr"
                "radarr"
                "lidarr"
              ];
              ntfy = {
                enable = true;
                topics = [ "media" ];
              };
            };
          };
        }
      ];
      script = s: config.config.systemd.services."${s}-notifications".script;
      has = s: triggers: lib.hasInfix (builtins.toJSON triggers) (script s);
    in
    pkgs.runCommand "unit-test-notif-default-triggers-unchanged" { } ''
      ${check "jellyfin sonarr defaults" (
        has "sonarr" [
          "onGrab"
          "onDownload"
          "onUpgrade"
          "onImportComplete"
          "onRename"
          "onSeriesAdd"
          "onSeriesDelete"
          "onEpisodeFileDelete"
          "onEpisodeFileDeleteForUpgrade"
          "onApplicationUpdate"
        ]
      )}
      ${check "jellyfin radarr defaults" (
        has "radarr" [
          "onGrab"
          "onDownload"
          "onUpgrade"
          "onRename"
          "onMovieDelete"
          "onMovieFileDelete"
          "onMovieFileDeleteForUpgrade"
          "onApplicationUpdate"
        ]
      )}
      ${check "jellyfin lidarr defaults" (
        has "lidarr" [
          "onGrab"
          "onReleaseImport"
          "onUpgrade"
          "onRename"
          "onArtistAdd"
          "onArtistDelete"
          "onHealthIssue"
          "onTrackRetag"
          "onApplicationUpdate"
        ]
      )}
      ${check "ntfy sonarr defaults" (
        has "sonarr" [
          "onGrab"
          "onDownload"
          "onUpgrade"
          "onImportComplete"
          "onSeriesAdd"
          "onSeriesDelete"
          "onEpisodeFileDelete"
          "onEpisodeFileDeleteForUpgrade"
          "onApplicationUpdate"
          "onManualInteractionRequired"
        ]
      )}
      ${check "ntfy radarr defaults" (
        has "radarr" [
          "onGrab"
          "onDownload"
          "onUpgrade"
          "onMovieAdded"
          "onMovieDelete"
          "onMovieFileDelete"
          "onMovieFileDeleteForUpgrade"
          "onApplicationUpdate"
          "onManualInteractionRequired"
        ]
      )}
      ${check "ntfy lidarr defaults" (
        has "lidarr" [
          "onGrab"
          "onReleaseImport"
          "onUpgrade"
          "onArtistAdd"
          "onArtistDelete"
          "onHealthIssue"
          "onDownloadFailure"
          "onImportFailure"
          "onApplicationUpdate"
        ]
      )}
      ${check "subsonic lidarr defaults" (
        has "lidarr" [
          "onGrab"
          "onReleaseImport"
          "onUpgrade"
          "onRename"
          "onArtistAdd"
          "onArtistDelete"
          "onHealthIssue"
          "onTrackRetag"
        ]
      )}
      echo 'PASS: notif-default-triggers-unchanged' > $out
    '';
}
