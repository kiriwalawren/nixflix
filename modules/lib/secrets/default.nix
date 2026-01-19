{lib}:
with lib;
let
  secretOrStrType = types.oneOf [
    types.str
    (types.submodule {
      options._secret = mkOption {
        type = types.str;
        description = "Path to a file containing the secret value";
      };
    })
  ];
in {
  isSecretRef = value:
    (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__);

  getSecretPath = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then value._secret
    else null;

  toShellValue = varName: value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "${varName}=$(cat ${escapeShellArg value._secret})"
    else "${varName}=${escapeShellArg (toString value)}";

  mkSecretAssertion = fieldName: value: {
    assertion = true; # Always true - we just want to warn, not fail
    message =
      if (builtins.isString value) && !(builtins.isAttrs value)
      then "Warning: ${fieldName} is set to a plain-text string. This will be visible in the Nix store. Consider using { _secret = /path/to/file; } instead for sensitive data."
      else "";
  };

  toPlaceholder = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "__SECRET_FILE__${toString value._secret}__"
    else toString value;

  processValue = value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__)
    then "__SECRET_FILE__${toString value._secret}__"
    else if isBool value
    then
      if value
      then "1"
      else "0"
    else if isList value
    then
      concatStringsSep ", " (map (
          v:
            if (builtins.isAttrs v) && (v ? _secret) && !(v ? __unfix__)
            then "__SECRET_FILE__${toString v._secret}__"
            else toString v
        )
        value)
    else if isAttrs value
    then mapAttrs (_name: processValue) value
    else if isInt value || isFloat value || isString value
    then toString value
    else toString value;

  mkSecretOption = {
    type ? secretOrStrType,
    default ? null,
    example ? null,
    description,
  }:
    mkOption {
      inherit type default;
      example =
        if example != null
        then example
        else literalExpression ''{ _secret = "/run/secrets/secret-file"; }'';
      description = ''
        ${description}
        Can be a plain string (visible in Nix store) or { _secret = /path/to/file; } for file-based secrets.
        Warning: Plain-text secrets will be visible in the Nix store. Use { _secret = path; } for sensitive data.
      '';
    };
}
