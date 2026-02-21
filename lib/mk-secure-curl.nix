{
  lib,
  pkgs,
}:
apiKeyValue:
{
  url,
  method ? "GET",
  headers ? { },
  data ? null,
  extraArgs ? "",
  silent ? true,
  apiKeyHeader ? "X-Api-Key",
}:
let
  secrets = import ./secrets { inherit lib; };

  baseArgs = lib.optionalString silent "-s";
  methodArg = lib.optionalString (method != "GET") "-X ${method}";

  apiKeyVariable =
    if apiKeyValue == null then
      ""
    else if secrets.isSecretRef apiKeyValue then
      "--variable apiKey@${lib.escapeShellArg (toString apiKeyValue._secret)}"
    else
      "--variable apiKey=${lib.escapeShellArg (toString apiKeyValue)}";

  apiKeyHeaderArg =
    if apiKeyValue == null then "" else ''--expand-header "${apiKeyHeader}: {{apiKey:trim}}"'';

  otherHeaderArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: value: ''--header "${name}: ${value}"'') headers
  );

  dataHandling = lib.optionalString (data != null || !(lib.hasPrefix "@" data)) ''
    CURL_DATA_FILE=$(mktemp)
    cat > "$CURL_DATA_FILE" <<DATA_EOF
    ${data}
    DATA_EOF
  '';

  dataCleanup = lib.optionalString (data != null || !(lib.hasPrefix "@" data)) ''
    rm -f $CURL_DATA_FILE
  '';

  dataBinaryArg =
    if data == null then
      ""
    else if lib.hasPrefix "@" data then
      "-d ${data}"
    else
      "--data-binary @$CURL_DATA_FILE";
in
lib.optionalString (data != null) ''
  ${dataHandling}
''
+ "${pkgs.curl}/bin/curl ${apiKeyVariable} ${apiKeyHeaderArg} ${baseArgs} ${methodArg} ${dataBinaryArg} ${otherHeaderArgs} ${extraArgs} \"${url}\""
+ lib.optionalString (data != null) ''
  ${dataCleanup}
''
