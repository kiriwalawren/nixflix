{
  pkgs,
  evalConfig,
  assertTest,
  check,
  ...
}:
let
  testPassword = pkgs.writeText "arr-auth-test-password" "test-only-password";
  testApiKey = pkgs.writeText "arr-auth-test-api-key" "test-only-api-key";
  testOidcSecret = pkgs.writeText "arr-oidc-test-secret" "test-only-oidc-secret";
in
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
                    password._secret = testPassword;
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
                  password._secret = testPassword;
                };
                apiKey._secret = testApiKey;
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

  hostconfig-oidc =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = testApiKey;
                hostConfig = {
                  authenticationMethod = "oidc";
                  trustedNetworks = "192.0.2.1";
                  username = null;
                  oidc = {
                    authority = "https://login.example.org";
                    clientId = "sonarr";
                    clientSecret._secret = testOidcSecret;
                    userIdentifier = "user@example.org";
                  };
                };
              };
            };
          };
        }
      ];
      script = config.config.systemd.services.sonarr-config.script;
    in
    pkgs.runCommand "unit-test-hostconfig-oidc" { } ''
      ${check "OIDC authentication is reflected in service environment" (
        config.config.systemd.services.sonarr.environment.SONARR__AUTH__METHOD == "Oidc"
      )}
      ${check "OIDC client secret is read from the supplied file" (
        pkgs.lib.hasInfix "--rawfile nixflixSecret0Content ${builtins.unsafeDiscardStringContext (toString testOidcSecret)}" script
      )}
      ${check "OIDC settings are included in the host configuration PUT" (
        pkgs.lib.hasInfix "oidcAuthority" script && pkgs.lib.hasInfix ".[\"oidcClientSecret\"] =" script
      )}
      ${check "OIDC secret value is not embedded in the service script" (
        !(pkgs.lib.hasInfix "test-only-oidc-secret" script)
      )}
      ${check "reverse proxy is trusted explicitly" (
        pkgs.lib.hasInfix "\"trustedNetworks\":\"192.0.2.1\"" script
      )}
      echo 'PASS: hostconfig-oidc' > $out
    '';

  hostconfig-oidc-requires-settings =
    let
      result =
        builtins.tryEval
          (evalConfig [
            {
              nixflix.enable = true;
              nixflix.radarr.enable = true;
              nixflix.radarr.config.hostConfig.authenticationMethod = "oidc";
            }
          ]).config.system.build.toplevel.drvPath;
    in
    assertTest "hostconfig-oidc-requires-settings" (!result.success);

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
                  password._secret = testPassword;
                };
                apiKey._secret = testApiKey;
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
