{
  pkgs,
  lib,
  evalConfig,
  assertTest,
  check,
  ...
}:
{
  # Test that nixflix.sonarr options generate correct systemd units
  sonarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/tv"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr && systemdUnits ? sonarr-config && systemdUnits ? sonarr-rootfolders;
    in
    assertTest "sonarr-service-generation" hasAllServices;

  # Test that nixflix.sonarr-anime options generate correct systemd units
  sonarr-anime-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr-anime = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8990;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr-anime
        && systemdUnits ? sonarr-anime-config
        && systemdUnits ? sonarr-anime-rootfolders;
    in
    assertTest "sonarr-anime-service-generation" hasAllServices;

  # Test that radarr options generate correct systemd units
  radarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? radarr && systemdUnits ? radarr-config && systemdUnits ? radarr-rootfolders;
    in
    assertTest "radarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  prowlarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            prowlarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 9696;
                  username = "admin";
                  password._secret = "/run/secrets/prowlarr-pass";
                };
                apiKey._secret = "/run/secrets/prowlarr-api";
                indexers = [
                  {
                    name = "1337x";
                    apiKey._secret = "/run/secrets/1337x-api";
                  }
                  {
                    name = "My Tracker";
                    schemaName = "Generic Torznab";
                    trackerId._secret = "/run/secrets/tracker-id";
                  }
                  {
                    name = "Other Tracker";
                    schemaName = "Generic Torznab";
                    baseUrl = "http://127.0.0.1:9117/other";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      indexersScript = systemdUnits.prowlarr-indexers.script;
    in
    pkgs.runCommand "unit-test-prowlarr-service-generation" { } ''
      ${check "prowlarr services are generated" (
        systemdUnits ? prowlarr && systemdUnits ? prowlarr-config && systemdUnits ? prowlarr-indexers
      )}
      ${check "schemaName is used for schema lookup" (
        lib.hasInfix "--arg name 'Generic Torznab' '.[] | select(.name == $name)" indexersScript
      )}
      ${check "display names are applied to indexers from the same schema" (
        lib.hasInfix "--arg name 'My Tracker' '.name = $name" indexersScript
        && lib.hasInfix "--arg name 'Other Tracker' '.name = $name" indexersScript
      )}
      ${check "secrets are read at runtime" (
        lib.hasInfix "--rawfile nixflixSecret1Content /run/secrets/1337x-api" indexersScript
        && lib.hasInfix "--rawfile nixflixSecret0Content /run/secrets/tracker-id" indexersScript
      )}
      echo 'PASS: prowlarr-service-generation' > $out
    '';

  # Test that prowlarr with indexers generates correct systemd units
  sabnzbd-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            usenetClients.sabnzbd = {
              enable = true;
              downloadsDir = "/downloads/usenet";
              settings = {
                misc = {
                  api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                  nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                  port = 8080;
                  host = "127.0.0.1";
                  url_base = "/sabnzbd";
                  ignore_samples = true;
                  direct_unpack = false;
                  article_tries = 5;
                };
                servers = [
                  {
                    name = "TestServer";
                    host = "news.example.com";
                    port = 563;
                    username._secret = pkgs.writeText "eweka-username" "testuser";
                    password._secret = pkgs.writeText "eweka-password" "testpass123";
                    connections = 10;
                    ssl = true;
                    priority = 0;
                  }
                ];
                categories = [
                  {
                    name = "tv";
                    dir = "tv";
                    priority = 0;
                    pp = 3;
                    script = "None";
                  }
                  {
                    name = "movies";
                    dir = "movies";
                    priority = 1;
                    pp = 2;
                    script = "None";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices = systemdUnits ? sabnzbd;
    in
    assertTest "sabnzbd-service-generation" hasAllServices;

  download-clients-no-reverse-proxy =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;

            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };

            usenetClients.sabnzbd = {
              enable = true;
              settings.misc = {
                api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                port = 8080;
                url_base = "/sabnzbd";
              };
            };

            downloadarr.sabnzbd = {
              removeCompletedDownloads = false;
              removeFailedDownloads = true;
              priority = 1;
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
      sabnzbdCfg = config.config.nixflix.usenetClients.sabnzbd;
      downloadClientsService = config.config.systemd.services."radarr-downloadclients";
    in
    pkgs.runCommand "unit-test-download-clients-no-reverse-proxy" { } ''
      ${check "radarr bindAddress is 127.0.0.1 when nginx is disabled" (
        radarrCfg.config.hostConfig.bindAddress == "127.0.0.1"
      )}
      ${check "radarr connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        radarrCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "sabnzbd connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        sabnzbdCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "radarr-downloadclients ExecStartPre uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients ExecStartPre does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients script uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.script
      )}
      ${check "radarr-downloadclients script does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.script
      )}
      ${check "apply_field_overrides merges top-level overrides (enable, freeform properties)" (
        lib.hasInfix ". + \$overrides" downloadClientsService.script
      )}
      ${check "sabnzbd download client enable is passed through as a top-level override" (
        lib.hasInfix ''"enable":true'' downloadClientsService.script
      )}
      ${check
        "sabnzbd freeform properties (removeCompletedDownloads/removeFailedDownloads/priority) are passed through"
        (
          lib.hasInfix ''"removeCompletedDownloads":false'' downloadClientsService.script
          && lib.hasInfix ''"removeFailedDownloads":true'' downloadClientsService.script
          && lib.hasInfix ''"priority":1'' downloadClientsService.script
        )
      }
      echo 'PASS: download-clients-no-reverse-proxy' > $out
    '';

  # LoadCredential replaces the old -env root service; verify the generated unit
  arr-load-credential =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
              };
            };
          };
        }
      ];
      services = config.config.systemd.services;
      svc = services.sonarr.serviceConfig;
    in
    pkgs.runCommand "unit-test-arr-load-credential" { } ''
      ${check "sonarr-env service no longer exists" (!services ? sonarr-env)}
      ${check "LoadCredential set for secret-ref apiKey" (
        builtins.elem "apiKey:/run/secrets/sonarr-api" svc.LoadCredential
      )}
      ${check "no EnvironmentFile" (!svc ? EnvironmentFile)}
      echo 'PASS: arr-load-credential' > $out
    '';

  # lidarr metadata/quality profile assertions: at least one profile must be present
  lidarr-qualityprofiles-empty-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                lidarr = {
                  enable = true;
                  config.qualityProfiles = [ ];
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "lidarr-qualityprofiles-empty-assertion" (!result.success);

  lidarr-metadataprofiles-empty-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                lidarr = {
                  enable = true;
                  config.metadataProfiles = [ ];
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "lidarr-metadataprofiles-empty-assertion" (!result.success);

  # Data dirs hold API keys (config.xml, settings.json, databases), so no
  # other local user may enter them.
  state-dirs-private =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/radarr-api";
            };
            sonarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/sonarr-api";
            };
            prowlarr = {
              enable = true;
              config.apiKey._secret = "/run/secrets/prowlarr-api";
            };
            seerr = {
              enable = true;
              apiKey._secret = "/run/secrets/seerr-api";
              jellyfin = {
                adminUsername = "admin";
                adminPassword = "password";
              };
            };
            maintainerr.enable = true;
          };
        }
      ];
      cfg = config.config;
      inherit (cfg.systemd.tmpfiles) settings;
      mode = svc: dir: settings."10-${svc}".${dir}.d.mode;
    in
    pkgs.runCommand "unit-test-state-dirs-private" { } ''
      ${check "radarr dataDir 0700" (mode "radarr" cfg.nixflix.radarr.dataDir == "0700")}
      ${check "sonarr dataDir 0700" (mode "sonarr" cfg.nixflix.sonarr.dataDir == "0700")}
      ${check "prowlarr dataDir 0700" (mode "prowlarr" cfg.nixflix.prowlarr.dataDir == "0700")}
      ${check "seerr dataDir 0700" (mode "seerr" cfg.nixflix.seerr.dataDir == "0700")}
      ${check "maintainerr dataDir 0700" (mode "maintainerr" cfg.nixflix.maintainerr.dataDir == "0700")}
      echo 'PASS: state-dirs-private' > $out
    '';
}
