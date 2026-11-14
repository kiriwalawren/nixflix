{
  pkgs,
  lib,
  evalConfig,
  assertTest,
  ...
}:
let
  # Seerr with a remote Jellyfin, plus whatever the test layers on top
  seerrWith =
    extra:
    evalConfig [
      {
        nixflix = {
          enable = true;
          seerr = {
            enable = true;
            apiKey._secret = "/run/secrets/seerr-api";
            jellyfin = {
              adminUsername = "remoteadmin";
              adminPassword = "remotepassword";
            };
          };
        };
      }
      extra
    ];

  pinchflatOn = {
    nixflix.pinchflat = {
      enable = true;
      selfhosted = true;
    };
  };

  # Shape of Seerr's POST /api/v1/settings/jellyfin/library/sync response
  libraryFixture = pkgs.writeText "seerr-libraries.json" (
    builtins.toJSON [
      {
        id = "1";
        name = "Shows";
        type = "show";
        enabled = false;
      }
      {
        id = "2";
        name = "Movies";
        type = "movie";
        enabled = false;
      }
      {
        id = "3";
        name = "YouTube";
        type = "show";
        enabled = false;
      }
    ]
  );

  # Checks the library selection, and that seerr-libraries really runs it
  librarySelectionTest =
    name: config: expected:
    let
      select = import ../../modules/seerr/librarySelect.nix {
        inherit lib pkgs;
        cfg = config.config.nixflix.seerr;
      };
      serviceScript = pkgs.writeText "seerr-libraries-script" config.config.systemd.services.seerr-libraries.script;
    in
    pkgs.runCommand "unit-test-${name}" { } ''
      # The exact jq selection seerr-library-sync runs, against the fixture
      got=$(${pkgs.jq}/bin/jq -r ${select.args} -f ${select.filter} ${libraryFixture})
      if [ "$got" != ${lib.escapeShellArg expected} ]; then
        echo "FAIL: ${name}: enabled ids are '$got', expected '${expected}'"
        exit 1
      fi
      echo "PASS: ${name}: enabled ids are $got"

      sync=$(grep -o '/nix/store/[^ "]*-seerr-library-sync' ${serviceScript} | head -n1)
      if [ -z "$sync" ] || ! grep -qF -- ${lib.escapeShellArg "-f ${select.filter}"} "$sync" \
        || ! grep -qF -- ${lib.escapeShellArg select.args} "$sync"; then
        echo "FAIL: ${name}: seerr-library-sync does not run the selection filter"
        exit 1
      fi
      echo "PASS: ${name}: seerr-library-sync runs the selection filter"
      echo 'PASS: ${name}' > $out
    '';
in
{
  # Test that seerr generates services with a remote Jellyfin (no local jellyfin)
  seerr-remote-jellyfin =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            seerr = {
              enable = true;
              apiKey._secret = "/run/secrets/seerr-api";
              jellyfin = {
                adminUsername = "remoteadmin";
                adminPassword = "remotepassword";
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
    in
    assertTest "seerr-remote-jellyfin" (
      systemdUnits ? seerr
      && systemdUnits ? seerr-setup
      && systemdUnits ? seerr-jellyfin
      && systemdUnits ? seerr-libraries
      && systemdUnits ? seerr-user-settings
    );

  # nixflix.seerr drives the 3.5.0+ library endpoints, so a package below that
  # must be caught at eval time rather than as `status=22` from seerr-setup.
  seerr-package-below-minimum-assertion =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            seerr = {
              enable = true;
              apiKey._secret = pkgs.writeText "seerr-apikey" "seerr-test-key";
              package = pkgs.seerr.overrideAttrs (old: {
                inherit (old) src;
                version = "3.4.1";
              });
            };
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
    in
    assertTest "seerr-package-below-minimum-assertion" (
      builtins.any (a: lib.hasInfix "requires Seerr 3.5.0 or newer" a.message) failed
    );

  # The nixpkgs nixflix pins must itself satisfy nixflix's minimum.
  seerr-pinned-package-meets-minimum =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            seerr = {
              enable = true;
              apiKey._secret = pkgs.writeText "seerr-apikey" "seerr-test-key";
            };
          };
        }
      ];
      failed = builtins.filter (a: !a.assertion) config.config.assertions;
    in
    assertTest "seerr-pinned-package-meets-minimum" (
      !(builtins.any (a: lib.hasInfix "requires Seerr 3.5.0 or newer" a.message) failed)
    );

  seerr-exclude-libraries-default-with-pinchflat =
    assertTest "seerr-exclude-libraries-default-with-pinchflat"
      ((seerrWith pinchflatOn).config.nixflix.seerr.jellyfin.excludeLibraries == [ "YouTube" ]);

  seerr-exclude-libraries-default-without-pinchflat =
    assertTest "seerr-exclude-libraries-default-without-pinchflat"
      ((seerrWith { }).config.nixflix.seerr.jellyfin.excludeLibraries == [ ]);

  # enableAllLibraries = true (the default): Shows and Movies stay, YouTube is left out
  seerr-library-sync-skips-youtube =
    librarySelectionTest "seerr-library-sync-skips-youtube" (seerrWith pinchflatOn)
      "1,2";

  seerr-library-sync-without-pinchflat-enables-all =
    librarySelectionTest "seerr-library-sync-without-pinchflat-enables-all" (seerrWith { })
      "1,2,3";

  # libraryFilter matches YouTube by type, the exclusion still wins
  seerr-library-sync-filter-skips-youtube =
    librarySelectionTest "seerr-library-sync-filter-skips-youtube"
      (seerrWith {
        imports = [ pinchflatOn ];
        nixflix.seerr.jellyfin = {
          enableAllLibraries = false;
          libraryFilter.types = [ "show" ];
        };
      })
      "1";

  # Setting the option replaces the default, so YouTube comes back
  seerr-exclude-libraries-override = librarySelectionTest "seerr-exclude-libraries-override" (
    seerrWith
      {
        imports = [ pinchflatOn ];
        nixflix.seerr.jellyfin.excludeLibraries = [ "Movies" ];
      }
  ) "1,3";
}
