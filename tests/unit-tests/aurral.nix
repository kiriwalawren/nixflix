{
  pkgs,
  lib,
  check,
  evalConfig,
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
      settings.users.admin = {
        username = "admin";
        role = "admin";
        password._secret = "/run/secrets/aurral-admin";
      };
    };
  };

  # Filtered by message because the bare harness always trips the fileSystems and grub assertions
  aurralFailures =
    overrides:
    lib.filter (a: !a.assertion && lib.hasInfix "aurral" (lib.toLower a.message))
      (evalConfig [ { nixflix = lib.recursiveUpdate baseNixflix overrides; } ]).config.assertions;

  failuresMatching =
    overrides: needle: lib.filter (a: lib.hasInfix needle a.message) (aurralFailures overrides);

  oidcFailures = aurralFailures { aurral.oidc.enable = true; };
in
{
  aurral-assertions = pkgs.runCommand "unit-test-aurral-assertions" { } ''
    ${check "a valid config trips no aurral assertions" (aurralFailures { } == [ ])}

    ${check "no admin user trips the admin assertion" (
      lib.length (
        failuresMatching { aurral.settings.users.admin.role = "user"; } "must have role = \"admin\""
      ) == 1
    )}

    ${check "disabled lidarr trips the lidarr assertion" (
      lib.length (failuresMatching { lidarr.enable = false; } "Aurral requires Lidarr") == 1
    )}

    ${check "oidc without issuer, clientId and clientSecret trips each assertion" (
      lib.all (field: lib.any (a: lib.hasInfix "nixflix.aurral.oidc.${field}" a.message) oidcFailures) [
        "issuer"
        "clientId"
        "clientSecret"
      ]
    )}

    ${check "complete oidc settings trip no aurral assertions" (
      aurralFailures {
        aurral.oidc = {
          enable = true;
          issuer = "https://auth.example.com";
          clientId._secret = "/run/secrets/oidc-id";
          clientSecret._secret = "/run/secrets/oidc-secret";
        };
      } == [ ]
    )}

    echo 'PASS: aurral-assertions' > $out
  '';
}
