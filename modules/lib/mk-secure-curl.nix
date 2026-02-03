{
  lib,
  pkgs,
}: apiKeyVar: {
  url,
  method ? "GET",
  headers ? {},
  data ? null,
  extraArgs ? "",
  silent ? true,
  apiKeyHeader ? "X-Api-Key",
}: let
  baseArgs = lib.optionalString silent "-s";
  methodArg = lib.optionalString (method != "GET") "-X ${method}";

  otherHeaders = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: ''header = "${name}: ${value}"'') headers
  );

  dataHandling = lib.optionalString (data != null) ''
    CURL_DATA_FILE=$(mktemp)
    trap "rm -f $CURL_DATA_FILE" EXIT
    cat > "$CURL_DATA_FILE" <<'DATA_EOF'
    ${data}
    DATA_EOF
  '';

  dataBinaryArg = lib.optionalString (data != null) "--data-binary @$CURL_DATA_FILE";
in
  lib.optionalString (data != null) ''
    ${dataHandling}
  ''
  + ''
    ${pkgs.curl}/bin/curl -K - ${baseArgs} ${methodArg} ${dataBinaryArg} ${extraArgs} "${url}" <<CURL_CONFIG
    header = "${apiKeyHeader}: ''$${apiKeyVar}"
    ${otherHeaders}
    CURL_CONFIG
  ''
