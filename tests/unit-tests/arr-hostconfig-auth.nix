{
  pkgs,
  evalConfig,
  assertTest,
  check,
  ...
}:
{
  # hostConfig assertion: username and password must both be set or both be null
  hostconfig-username-requires-password =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = "admin";
                    # password left at default null
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-username-requires-password" (!result.success);

  hostconfig-password-requires-username =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = null;
                    password._secret = "/run/secrets/sonarr-pass";
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-password-requires-username" (!result.success);

  # https://github.com/kiriwalawren/nixflix/issues/270
  # settings.auth/settings.server must mirror config.hostConfig so that the
  # environment variables actually reflect what the user configured there.
  hostconfig-drives-settings-auth =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  urlBase = "/radarr";
                  authenticationMethod = "external";
                  authenticationRequired = "disabledForLocalAddresses";
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
      radarrCfg = config.config.nixflix.radarr;
      environment = config.config.systemd.services.radarr.environment;
    in
    pkgs.runCommand "unit-test-hostconfig-drives-settings-auth" { } ''
      ${check "settings.auth.method mirrors hostConfig.authenticationMethod" (
        radarrCfg.settings.auth.method == "External"
      )}
      ${check "settings.auth.required mirrors hostConfig.authenticationRequired" (
        radarrCfg.settings.auth.required == "DisabledForLocalAddresses"
      )}
      ${check "settings.server.port mirrors hostConfig.port" (radarrCfg.settings.server.port == 7878)}
      ${check "settings.server.urlBase mirrors hostConfig.urlBase" (
        radarrCfg.settings.server.urlBase == "/radarr"
      )}
      ${check "RADARR__AUTH__METHOD env var reflects hostConfig" (
        environment.RADARR__AUTH__METHOD == "External"
      )}
      ${check "RADARR__AUTH__REQUIRED env var reflects hostConfig" (
        environment.RADARR__AUTH__REQUIRED == "DisabledForLocalAddresses"
      )}
      echo 'PASS: hostconfig-drives-settings-auth' > $out
    '';

  # A user should be able to override settings.auth directly (normal priority,
  # no lib.mkForce needed) since the hostConfig-derived value is only mkDefault.
  settings-auth-overrides-hostconfig =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  authenticationMethod = "forms";
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
              settings.auth.method = "External";
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
    in
    assertTest "settings-auth-overrides-hostconfig" (radarrCfg.settings.auth.method == "External");
}
