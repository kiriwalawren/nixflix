{
  pkgs,
  lib,
  check,
  evalConfig,
  evalConfigWith,
  nixpkgs-2026-09-03,
  ...
}:
let
  baseNixflix = {
    enable = true;

    lidarr = {
      enable = true;
      config = {
        hostConfig.password._secret = "/run/secrets/lidarr-pass";
        apiKey._secret = "/run/secrets/lidarr-api";
      };
    };

    aurral = {
      enable = true;
      apiKey._secret = "/run/secrets/aurral-api";
      settings.users.admin = {
        username = "admin";
        role = "admin";
        password._secret = "/run/secrets/aurral-admin";
      };
    };
  };

  # Filtered by message because the bare harness always trips the fileSystems and grub assertions
  failuresWith =
    eval: overrides:
    lib.filter (a: !a.assertion && lib.hasInfix "aurral" (lib.toLower a.message))
      (eval [ { nixflix = lib.recursiveUpdate baseNixflix overrides; } ]).config.assertions;

  aurralFailures = failuresWith evalConfig;

  failuresMatching =
    overrides: needle: lib.filter (a: lib.hasInfix needle a.message) (aurralFailures overrides);

  oidcFailures = aurralFailures { aurral.oidc.enable = true; };

  completeOidc = {
    enable = true;
    issuer = "https://auth.example.com";
    clientId._secret = "/run/secrets/oidc-id";
    clientSecret._secret = "/run/secrets/oidc-secret";
  };

  # This nixpkgs crashes rendering its fileSystems assertion message, so satisfy it instead
  oldFailures = failuresWith (
    modules:
    evalConfigWith nixpkgs-2026-09-03 (
      [
        {
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
        }
      ]
      ++ modules
    )
  );

  aurralConfig =
    overrides: (evalConfig [ { nixflix = lib.recursiveUpdate baseNixflix overrides; } ]).config;

  apiKeyScript = overrides: (aurralConfig overrides).systemd.services.aurral-env.script;

  oidcScript = overrides: (aurralConfig overrides).systemd.services.aurral-oidc-env.script;

  lidarrService = overrides: (aurralConfig overrides).systemd.services.aurral-lidarr;

  withoutApiKey =
    (evalConfig [
      {
        nixflix = baseNixflix // {
          aurral = removeAttrs baseNixflix.aurral [ "apiKey" ];
        };
      }
    ]).config;

  countLines =
    needle: script: lib.length (lib.filter (lib.hasPrefix needle) (lib.splitString "\n" script));

  validApiKey = "0123456789abcdef0123456789abcdef";

  missingServiceAurral = lib.filter (a: lib.hasInfix "provides `services.aurral`" a.message);
in
{
  aurral-assertions = pkgs.runCommand "unit-test-aurral-assertions" { } ''
    ${check "a valid config trips no aurral assertions" (aurralFailures { } == [ ])}

    ${check "no admin user trips the admin assertion" (
      lib.length (
        failuresMatching { aurral.settings.users.admin.role = "user"; } "must have role = \"admin\""
      ) == 1
    )}

    ${check "disabled lidarr trips no aurral assertions" (
      aurralFailures { lidarr.enable = false; } == [ ]
    )}

    ${check "oidc without issuer, clientId and clientSecret trips each assertion" (
      lib.all (field: lib.any (a: lib.hasInfix "nixflix.aurral.oidc.${field}" a.message) oidcFailures) [
        "issuer"
        "clientId"
        "clientSecret"
      ]
    )}

    ${check "complete oidc settings trip no aurral assertions" (
      aurralFailures { aurral.oidc = completeOidc; } == [ ]
    )}

    ${check "an aurral package below 2.13.0 trips the version assertion" (
      lib.length (
        failuresMatching {
          aurral.package = pkgs.aurral.overrideAttrs (old: {
            inherit (old) src;
            version = "2.12.0";
          });
        } "requires Aurral 2.13.0 or newer"
      ) == 1
    )}

    ${check "a plain apiKey shorter than 32 characters trips the length assertion" (
      lib.length (failuresMatching { aurral.apiKey = "too-short"; } "must be at least 32 characters") == 1
    )}

    ${check "a 32 character plain apiKey trips no aurral assertions" (
      aurralFailures { aurral.apiKey = validApiKey; } == [ ]
    )}

    ${check "a secret apiKey trips no aurral assertions" (
      aurralFailures { aurral.apiKey._secret = "/run/secrets/aurral-api"; } == [ ]
    )}

    echo 'PASS: aurral-assertions' > $out
  '';

  aurral-env-file = pkgs.runCommand "unit-test-aurral-env-file" { } ''
    ${check "omitting apiKey fails evaluation" (
      !(builtins.tryEval withoutApiKey.systemd.services.aurral-env.script).success
    )}

    ${check "apiKey writes AURRAL_API_KEY to its env file" (
      lib.hasInfix "AURRAL_API_KEY=$(cat /run/secrets/aurral-api)" (apiKeyScript {
        aurral.apiKey._secret = "/run/secrets/aurral-api";
      })
    )}

    ${check "apiKey and oidc env files are both loaded by aurral" (
      let
        envFiles =
          (aurralConfig {
            aurral.apiKey = validApiKey;
            aurral.oidc = completeOidc;
          }).systemd.services.aurral.serviceConfig.EnvironmentFile;
      in
      lib.elem "/run/aurral/env" envFiles && lib.elem "/run/aurral/api-key.env" envFiles
    )}

    ${check "oidc writes each client variable exactly once and no AURRAL_API_KEY" (
      let
        script = oidcScript { aurral.oidc = completeOidc; };
      in
      countLines "OIDC_CLIENT_ID=" script == 1
      && countLines "OIDC_CLIENT_SECRET=" script == 1
      && countLines "AURRAL_API_KEY=" script == 0
    )}

    echo 'PASS: aurral-env-file' > $out
  '';

  aurral-lidarr = pkgs.runCommand "unit-test-aurral-lidarr" { } ''
    ${check "enabled lidarr configures lidarr profiles after lidarr-config" (
      let
        svc = lidarrService { };
      in
      lib.hasInfix "/settings/lidarr/metadata-profiles" svc.script
      && lib.elem "lidarr-config.service" svc.after
      && lib.elem "lidarr-config.service" svc.requires
    )}

    ${check "disabled lidarr disables the integration without lidarr-config" (
      let
        svc = lidarrService { lidarr.enable = false; };
      in
      lib.hasInfix ''"lidarr":{"enabled":false}'' svc.script
      && !(lib.hasInfix "/settings/lidarr/profiles" svc.script)
      && !(lib.elem "lidarr-config.service" svc.after)
      && !(lib.elem "lidarr-config.service" svc.requires)
    )}

    echo 'PASS: aurral-lidarr' > $out
  '';

  # nixflix must keep evaluating on a nixpkgs that predates services.aurral
  aurral-nixpkgs-without-services-aurral =
    pkgs.runCommand "unit-test-aurral-nixpkgs-without-services-aurral" { }
      ''
        ${check "nixflix evaluates with aurral disabled" (oldFailures { aurral.enable = false; } == [ ])}

        ${check "enabling aurral trips the services.aurral assertion" (
          lib.length (missingServiceAurral (oldFailures { })) == 1
        )}

        ${check "enabling oidc does not define services.aurral either" (
          lib.length (
            missingServiceAurral (oldFailures {
              aurral.oidc = completeOidc;
            })
          ) == 1
        )}

        echo 'PASS: aurral-nixpkgs-without-services-aurral' > $out
      '';
}
