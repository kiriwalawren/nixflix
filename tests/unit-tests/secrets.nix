{
  pkgs,
  lib,
  check,
  ...
}:
let
  secrets = import ../../lib/secrets { inherit lib; };
in
{
  nested-secret-in-list-jq-filter =
    let
      rawConfig = {
        Entries = [
          {
            Name = "first";
            Value._secret = secretFile;
          }
        ];
      };
      secretFile = pkgs.writeText "entry-value" "s3cr3t-value\n";
      plainFile = pkgs.writeText "plain.json" (builtins.toJSON (secrets.stripSecretRefs rawConfig));
      jqSecrets = secrets.mkNestedJqSecretArgs rawConfig;
    in
    pkgs.runCommand "unit-test-nested-secret-in-list-jq-filter" { nativeBuildInputs = [ pkgs.jq ]; } ''
      merged=$(
        echo '{"Entries":[]}' \
          | jq \
              ${jqSecrets.flagsString} \
              --argjson plain "$(cat ${plainFile})" \
              '. * $plain | ${lib.concatStringsSep " | " jqSecrets.assignments}'
      )

      value=$(echo "$merged" | jq -r '.Entries[0].Value')
      if [ "$value" != "s3cr3t-value" ]; then
        echo "FAIL: expected substituted value, got '$value'" && exit 1
      fi
      echo 'PASS: nested-secret-in-list-jq-filter' > $out
    '';

  # mkOneOrMoreSecretsOption is the public way to accept `x` or `[ x ... ]`
  # (sabnzbd's rss uri): a single value must be normalised to a list, and the
  # item type must still be enforced per item.
  one-or-more-secrets-option =
    let
      evalValue =
        value:
        (lib.evalModules {
          modules = [
            {
              options.item = secrets.mkOneOrMoreSecretsOption {
                type = lib.types.nonEmptyStr;
                description = "test option";
              };
              config.item = value;
            }
          ];
        }).config.item;
      fails = value: !(builtins.tryEval (builtins.deepSeq (evalValue value) true)).success;
    in
    pkgs.runCommand "unit-test-one-or-more-secrets-option" { } ''
      ${check "a single value becomes a one-element list" (evalValue "a" == [ "a" ])}
      ${check "a list is kept as-is" (
        evalValue [
          "a"
          "b"
        ] == [
          "a"
          "b"
        ]
      )}
      ${check "a single secret becomes a one-element list" (
        builtins.map (v: v._secret or v) (evalValue {
          _secret = "/run/secrets/x";
        }) == [ "/run/secrets/x" ]
      )}
      ${check "an empty string is rejected" (fails "")}
      ${check "an empty list is rejected" (fails [ ])}
      ${check "an empty string item is rejected" (fails [ "" ])}
      ${check "a non-string is rejected" (fails 42)}
      echo 'PASS: one-or-more-secrets-option' > $out
    '';
}
