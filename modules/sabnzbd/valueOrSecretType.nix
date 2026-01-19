{lib}: let
  secrets = import ../lib/secrets {inherit lib;};
in {
  inherit (secrets) isSecretRef processValue;
}
