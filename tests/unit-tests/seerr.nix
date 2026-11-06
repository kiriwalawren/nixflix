{
  pkgs,
  lib,
  evalConfig,
  assertTest,
  ...
}:
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
}
