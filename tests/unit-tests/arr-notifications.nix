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

            notif.jellyfin.sonarr =
              lib.genAttrs [
                "onGrab"
                "onUpgrade"
                "onImportComplete"
                "onRename"
                "onSeriesAdd"
                "onSeriesDelete"
                "onEpisodeFileDelete"
                "onEpisodeFileDeleteForUpgrade"
                "onApplicationUpdate"
              ] (_: false)
              // {
                onHealthIssue = true;
              };

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
                sonarr.enable = true;
                topics = [ "media" ];
                password._secret = ntfyPasswordFile;
              };
              extraNotifications = [
                {
                  name = "Gotify";
                  implementationName = "Gotify";
                  sonarr.enable = true;
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
              lib.genAttrs
                (lib.filter (expectedOn name) [
                  "sonarr"
                  "radarr"
                  "lidarr"
                ])
                (_: {
                  enable = true;
                })
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
      ${check "every trigger lives in the service block" (evaluates {
        gotify.radarr.onGrab = false;
      })}
      ${check "a trigger at the connector root is rejected" (!evaluates { gotify.onGrab = true; })}
      ${check "an undeclared top-level name is rejected" (!evaluates { gotify.bogusField = true; })}
      ${check "a service block that the schema lacks is rejected" (
        !evaluates { pushsafer.sonarr.onDownload = true; }
      )}
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
                radarr.enable = true;
                apiKey = "plain-notifiarr-key";
              };
              ntfy = {
                radarr.enable = true;
                topics = [ "media" ];
                userName = "ntfy-user";
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
      ${check "ntfy userName is sent as the schema field userName" (
        lib.hasInfix ''"userName":"ntfy-user"'' script
      )}
      ${check "field-named overrides are not merged into the top level" (
        lib.hasInfix "select(.key as $k | $fieldNames | index($k) == null)" script
      )}
      echo 'PASS: notif-field-names' > $out
    '';

  notif-removed-options =
    let
      # Filtered by message because the bare harness always trips the
      # fileSystems and grub assertions.
      removedAssertions =
        notif:
        map (a: a.message) (
          lib.filter (a: !a.assertion && lib.hasInfix "has been removed" a.message)
            (evalConfig [
              {
                nixflix = {
                  enable = true;
                  inherit notif;
                };
              }
            ]).config.assertions
        );
      ntfyUsername = removedAssertions { ntfy.username = "old-user"; };
      gotifyServices = removedAssertions { gotify.services = [ "sonarr" ]; };
      discordEnable = removedAssertions { discord.enable = true; };
      extraEnable = removedAssertions {
        extraNotifications = [
          {
            name = "Extra Gotify";
            implementationName = "Gotify";
            enable = false;
            services = [ "sonarr" ];
            triggers.sonarr = [ "onGrab" ];
          }
        ];
      };
      jellyfinTriggers = removedAssertions {
        jellyfin = {
          apiKey = "test-jellyfin-key";
          triggers.sonarr = [ "onDownload" ];
        };
      };
      disabledNotif = removedAssertions {
        enable = false;
        subsonic.triggers.lidarr = [ "onGrab" ];
      };
    in
    pkgs.runCommand "unit-test-notif-removed-options" { } ''
      ${check "no removed-option assertion fires by default" (removedAssertions { } == [ ])}
      ${check "services fails on a named connector and points to the per-service enable options" (
        lib.length gotifyServices == 1
        && lib.hasInfix "nixflix.notif.gotify.services" (lib.head gotifyServices)
        && lib.hasInfix "nixflix.notif.gotify.radarr.enable = true;" (lib.head gotifyServices)
      )}
      ${check "a connector-level enable fails and points to the per-service enable options" (
        lib.length discordEnable == 1
        && lib.hasInfix "nixflix.notif.discord.enable" (lib.head discordEnable)
        && lib.hasInfix "nixflix.notif.discord.radarr.enable = true;" (lib.head discordEnable)
      )}
      ${check
        "enable, services and triggers on an extraNotifications entry fail and point to the service blocks"
        (
          lib.length extraEnable == 3
          && lib.all (
            m: lib.hasInfix "Extra Gotify" m && lib.hasInfix "radarr = { enable = true; onGrab = true; };" m
          ) extraEnable
        )
      }
      ${check "ntfy.username fails and points to ntfy.userName" (
        lib.length ntfyUsername == 1
        && lib.hasInfix "nixflix.notif.ntfy.username" (lib.head ntfyUsername)
        && lib.hasInfix "nixflix.notif.ntfy.userName" (lib.head ntfyUsername)
      )}
      ${check "the jellyfin triggers list fails and points to the boolean options" (
        lib.length jellyfinTriggers == 1
        && lib.hasInfix "nixflix.notif.jellyfin.triggers" (lib.head jellyfinTriggers)
        && lib.hasInfix "nixflix.notif.jellyfin.sonarr.onGrab" (lib.head jellyfinTriggers)
      )}
      ${check "a removed option fails even when notif is disabled" (lib.length disabledNotif == 1)}
      echo 'PASS: notif-removed-options' > $out
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
              sonarr.enable = true;
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
              notif = lib.mapAttrs (_: c: c // { sonarr.enable = true; }) notif;
            };
          }
        ]).config.systemd.services."sonarr-notifications".script;
      gotify = scriptFor {
        gotify = {
          tags = [
            "anime"
            "4k"
          ];
        };
      };
      ntfy = scriptFor {
        ntfy = {
          topics = [ "media" ];
          ntfyTags = [ "warning" ];
          tags = [ "anime" ];
        };
      };
      apprise = scriptFor {
        apprise = {
          appriseTags = [ "family" ];
        };
      };
      untagged = scriptFor { gotify = { }; };
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
              sonarr = {
                enable = true;
                onGrab = false;
                onSeriesAdd = false;
              };
              sonarr-anime = {
                enable = true;
                onGrab = false;
              };
              radarr = {
                enable = true;
                onGrab = false;
                onHealthIssue = true;
              };
              lidarr = {
                enable = true;
                onGrab = false;
              };
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
      ${check "sonarr-anime has its own block, unaffected by the sonarr block" (
        lib.hasInfix ''["onDownload","onUpgrade","onImportComplete","onSeriesAdd","onSeriesDelete",'' (
          script "sonarr-anime"
        )
      )}
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
                sonarr = {
                  enable = true;
                  includeSeriesPoster = true;
                };
                radarr = {
                  enable = true;
                  metadataLinks = [ 0 ];
                };
                lidarr.enable = true;
              };
              email = {
                sonarr.enable = true;
                lidarr = {
                  enable = true;
                  requireEncryption = true;
                };
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

  notif-per-service-overrides =
    let
      arr = port: {
        enable = true;
        config = {
          hostConfig.port = port;
          apiKey._secret = "/run/secrets/api";
        };
      };
      services = {
        sonarr = arr 8989;
        sonarr-anime = arr 8990;
        radarr = arr 7878;
        lidarr = arr 8686;
      };
      eval =
        notif:
        (evalConfig [
          {
            nixflix = services // {
              enable = true;
              inherit notif;
            };
          }
        ]).config.systemd.services;
      on =
        svcs:
        lib.genAttrs svcs (_: {
          enable = true;
        });
      allOn = on (lib.attrNames services);
      defaults = eval {
        discord = allOn // {
          webHookUrl = "https://discord.example/hook";
        };
      };
      overridden = eval {
        discord = lib.recursiveUpdate allOn {
          webHookUrl = "https://discord.example/hook";
          username = "Bot";
          lidarr.username = "Music Bot";
        };
        slack = lib.recursiveUpdate allOn {
          channel = "media";
          radarr.channel = "movies";
          sonarr.onGrab = true;
          sonarr-anime = {
            onGrab = false;
            name = "Anime Slack";
            tags = [ "anime" ];
          };
        };
        gotify = on [ "sonarr" ];
      };
      script = svcs: s: svcs."${s}-notifications".script;
      username =
        svcs: s: name:
        lib.hasInfix ''"username":"${name}"'' (script svcs s);
    in
    pkgs.runCommand "unit-test-notif-per-service-overrides" { } ''
      ${check "discord posts as the service name by default" (
        username defaults "sonarr" "Sonarr"
        && username defaults "sonarr-anime" "Sonarr Anime"
        && username defaults "radarr" "Radarr"
        && username defaults "lidarr" "Lidarr"
      )}
      ${check "the connector-level discord username replaces the service names" (
        username overridden "sonarr" "Bot"
        && username overridden "sonarr-anime" "Bot"
        && username overridden "radarr" "Bot"
      )}
      ${check "a per-service discord username beats the connector-level one" (
        username overridden "lidarr" "Music Bot"
      )}
      ${check "a per-service field override applies to that service only" (
        lib.hasInfix ''"channel":"movies"'' (script overridden "radarr")
        && lib.hasInfix ''"channel":"media"'' (script overridden "sonarr")
      )}
      ${check "a per-service trigger override beats the shared trigger" (
        lib.hasInfix ''["onGrab",'' (script overridden "sonarr")
        && lib.hasInfix ''["onDownload","onUpgrade","onImportComplete","onRename","onSeriesAdd",'' (
          script overridden "sonarr-anime"
        )
      )}
      ${check "name can be overridden per service" (
        lib.hasInfix "Anime Slack" (script overridden "sonarr-anime")
        && !lib.hasInfix "Anime Slack" (script overridden "sonarr")
      )}
      ${check "tags can be overridden per service" (
        lib.hasInfix "resolve_tag_id anime" (script overridden "sonarr-anime")
        && !lib.hasInfix "resolve_tag_id anime" (script overridden "sonarr")
      )}
      ${check "a service block is skipped unless it is enabled" (
        !lib.hasInfix "Processing notification: Gotify" (script overridden "sonarr-anime")
        && lib.hasInfix "Processing notification: Gotify" (script overridden "sonarr")
      )}
      echo 'PASS: notif-per-service-overrides' > $out
    '';

  notif-extra-notifications =
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
            notif.extraNotifications = [
              {
                name = "Extra Discord";
                implementationName = "Discord";
                username = "Extra";
                sonarr = {
                  enable = true;
                  onGrab = true;
                  onDownload = true;
                  onUpgrade = false;
                };
                radarr = {
                  enable = true;
                  onHealthIssue = true;
                  username = "Extra Movies";
                };
                lidarr.onGrab = true;
              }
            ];
          };
        }
      ];
      script = s: config.config.systemd.services."${s}-notifications".script;
    in
    pkgs.runCommand "unit-test-notif-extra-notifications" { } ''
      ${check "triggers set to true in a service block are enabled on that service" (
        lib.hasInfix ''--argjson enabledTriggers '["onDownload","onGrab"]' '' (script "sonarr")
        && lib.hasInfix ''--argjson enabledTriggers '["onHealthIssue"]' '' (script "radarr")
      )}
      ${check "triggers are not sent as field overrides" (
        !lib.hasInfix ''"onGrab":'' (script "sonarr") && !lib.hasInfix ''"enable":'' (script "sonarr")
      )}
      ${check "a field in a service block overrides the top-level value for that service only" (
        lib.hasInfix ''"username":"Extra Movies"'' (script "radarr")
        && lib.hasInfix ''"username":"Extra"'' (script "sonarr")
      )}
      ${check "an entry is skipped on a service whose block is not enabled" (
        !(config.config.systemd.services ? lidarr-notifications)
      )}
      echo 'PASS: notif-extra-notifications' > $out
    '';

  notif-seerr =
    let
      eval =
        notif:
        (evalConfig [
          {
            nixflix = {
              enable = true;
              seerr = {
                enable = true;
                apiKey = "seerr-key";
              };
              jellyfin = {
                enable = true;
                apiKey = "jellyfin-key";
                users.admin = {
                  password = "testpassword";
                  policy.isAdministrator = true;
                };
              };
              sonarr = {
                enable = true;
                config.apiKey._secret = "/run/secrets/sonarr-api";
              };
              inherit notif;
            };
          }
        ]).config;
      scriptOf = c: c.systemd.services.seerr-notifications.script;
      seerrFailures =
        c: map (a: a.message) (lib.filter (a: !a.assertion && lib.hasInfix "eerr" a.message) c.assertions);
      discord = {
        webHookUrl = "https://discord.example/starr";
        sonarr.enable = true;
        seerr.enable = true;
      };
      defaults = eval { inherit discord; };
      tuned = eval {
        discord = lib.recursiveUpdate discord {
          seerr = {
            webHookUrl = "https://discord.example/seerr";
            onIssueComment = false;
          };
        };
        email = {
          server = "smtp.example";
          port = 587;
          from = "seerr@example.com";
          username = "mailer";
          seerr = {
            enable = true;
            useEncryption = 1;
          };
        };
        ntfy = {
          topics = [ "media" ];
          ntfyTags = [
            "tv"
            "warning"
          ];
          accessToken = "ntfy-token";
          seerr.enable = true;
        };
        webhook = {
          url = "https://hook.example";
          username = "bob";
          password = "pw";
          seerr.enable = true;
        };
      };
      disabledDiscord = eval { discord = removeAttrs discord [ "seerr" ]; };
      failures = seerrFailures (eval {
        discord = {
          seerr.enable = true;
        };
        telegram = {
          botToken = "t";
          seerr.enable = true;
        };
        ntfy = {
          topics = [
            "a"
            "b"
          ];
          seerr.enable = true;
        };
        email = {
          server = "smtp.example";
          from = "a@example.com";
          seerr = {
            enable = true;
            pgpPassword = "x";
          };
        };
        webhook = {
          url = "https://hook.example";
          username = "a";
          seerr = {
            enable = true;
            authHeader = "Bearer x";
          };
        };
        extraNotifications = [
          {
            implementationName = "Discord";
            name = "extra";
            seerr.onMediaPending = true;
          }
        ];
      });
      hasFailure = needle: lib.any (lib.hasInfix needle) failures;
      options = (eval { }).nixflix.notif;
    in
    pkgs.runCommand "unit-test-notif-seerr" { } ''
      ${check "discord posts to Seerr as Seerr with every event on" (
        lib.hasInfix ''"botUsername":"Seerr"'' (scriptOf defaults)
        && lib.hasInfix ''"webhookUrl":"https://discord.example/starr"'' (scriptOf defaults)
        && lib.hasInfix ''"types":8158'' (scriptOf defaults)
      )}
      ${check "a seerr block override and a disabled event reach Seerr only" (
        lib.hasInfix ''"webhookUrl":"https://discord.example/seerr"'' (scriptOf tuned)
        && lib.hasInfix ''"types":7646'' (scriptOf tuned)
        && lib.hasInfix "https://discord.example/starr" tuned.systemd.services.sonarr-notifications.script
      )}
      ${check "seerr block options use nixflix names" (
        options.discord.seerr ? username && !(options.discord.seerr ? botUsername)
      )}
      ${check "email maps to the Seerr SMTP options without event types" (
        lib.hasInfix ''"smtpHost":"smtp.example"'' (scriptOf tuned)
        && lib.hasInfix ''"authUser":"mailer"'' (scriptOf tuned)
        && !(options.email.seerr ? onMediaPending)
        && options.discord.seerr ? onMediaPending
      )}
      ${check "email useEncryption is mapped onto the Seerr TLS flags" (
        lib.hasInfix ".options.requireTls = ($e == 1 and .options.smtpPort != 465)" (scriptOf tuned)
      )}
      ${check "ntfy joins tags and enables token auth" (
        lib.hasInfix ''"tags":"tv,warning"'' (scriptOf tuned)
        && lib.hasInfix ''"authMethodToken":true'' (scriptOf tuned)
        && lib.hasInfix ''"topic":"media"'' (scriptOf tuned)
      )}
      ${check "webhook username and password become a Basic authorization header" (
        lib.hasInfix ''"__basicUser":"bob"'' (scriptOf tuned) && lib.hasInfix "@base64" (scriptOf tuned)
      )}
      ${check "agents nixflix does not target are disabled" (
        lib.hasInfix "for agent in email gotify ntfy pushbullet pushover slack telegram webhook webpush; do" (
          scriptOf defaults
        )
      )}
      ${check "a connector does not target Seerr unless its seerr block is enabled" (
        lib.hasInfix "for agent in discord email" (scriptOf disabledDiscord)
        &&
          seerrFailures (eval {
            telegram.botToken = "t";
          }) == [ ]
      )}
      ${check "a missing required field names both option paths" (
        hasFailure "Set `nixflix.notif.discord.webHookUrl` or `nixflix.notif.discord.seerr.webHookUrl`."
      )}
      ${check "telegram requires chatId while events are on" (
        hasFailure "`nixflix.notif.telegram` is enabled for Seerr, but `chatId` is not set."
      )}
      ${check "email PGP key and password require each other" (
        hasFailure "Set `nixflix.notif.email.seerr.pgpPrivateKey`."
      )}
      ${check "ntfy needs exactly one topic for Seerr" (hasFailure "single topic")}
      ${check "webhook authHeader conflicts with username/password" (
        hasFailure "sends a single Authorization header"
      )}
      ${check "extraNotifications cannot target Seerr" (
        hasFailure "`nixflix.notif.extraNotifications` entry `extra` cannot target Seerr"
      )}
      ${check "service blocks are opt-in except the jellyfin ones" (
        !options.discord.seerr.enable
        && !options.gotify.sonarr.enable
        && !options.webpush.seerr.enable
        && options.jellyfin.sonarr.enable
      )}
      ${check "Starr triggers are only in service blocks" (
        !(options.gotify ? onGrab) && options.gotify.sonarr ? onGrab
      )}
      echo 'PASS: notif-seerr' > $out
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
              jellyfin.lidarr.enable = true;
              ntfy = {
                topics = [ "media" ];
                sonarr.enable = true;
                radarr.enable = true;
                lidarr.enable = true;
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
