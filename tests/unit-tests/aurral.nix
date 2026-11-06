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
      aurralFailures { aurral.oidc = completeOidc; } == [ ]
    )}

    echo 'PASS: aurral-assertions' > $out
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
