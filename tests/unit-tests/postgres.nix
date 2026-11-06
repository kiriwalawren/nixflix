{
  pkgs,
  lib,
  evalConfig,
  check,
  ...
}:
{
  postgres-external-host-requires-passwords-assertion =
    let
      failingAssertions =
        { host, withPasswords }:
        let
          password = lib.optionalAttrs withPasswords { postgres.password._secret = "/run/secrets/db"; };
        in
        lib.filter (entry: !entry.assertion && lib.hasInfix "needs a database password" entry.message)
          (evalConfig [
            {
              nixflix = {
                enable = true;
                postgres = {
                  enable = true;
                  inherit host;
                };
                sonarr = {
                  enable = true;
                  config.apiKey._secret = "/run/secrets/sonarr-api";
                }
                // password;
                seerr = {
                  enable = true;
                  apiKey._secret = "/run/secrets/seerr-api";
                }
                // password;
              };
            }
          ]).config.assertions;

      missing = failingAssertions {
        host = "192.168.1.10";
        withPasswords = false;
      };
      provided = failingAssertions {
        host = "192.168.1.10";
        withPasswords = true;
      };
      local = failingAssertions {
        host = null;
        withPasswords = false;
      };
      mentions = option: lib.any (entry: lib.hasInfix option entry.message) missing;
    in
    pkgs.runCommand "unit-test-postgres-external-host-requires-passwords-assertion" { } ''
      ${check "missing passwords trip one assertion per service" (lib.length missing == 2)}
      ${check "the Sonarr assertion names its option" (mentions "nixflix.sonarr.postgres.password")}
      ${check "the Seerr assertion names its option" (mentions "nixflix.seerr.postgres.password")}
      ${check "set passwords trip no assertions" (provided == [ ])}
      ${check "the local server needs no passwords" (local == [ ])}

      echo 'PASS: postgres-external-host-requires-passwords-assertion' > $out
    '';
}
