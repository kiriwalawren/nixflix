{ lib }:
with lib;
let
  secretOrStrType = types.oneOf [
    types.str
    (types.submodule {
      options._secret = mkOption {
        type = types.oneOf [
          types.str
          types.path
        ];
        description = "Path to a file containing the secret value";
      };
    })
  ];
in
rec {
  isSecretRef = value: (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__);

  toShellValue =
    value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__) then
      "$(cat ${escapeShellArg value._secret})"
    else
      "${escapeShellArg (toString value)}";

  processValue =
    value:
    if (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__) then
      "__SECRET_FILE__${toString value._secret}__"
    else if isBool value then
      if value then "1" else "0"
    else if isList value then
      concatStringsSep ", " (
        map (
          v:
          if (builtins.isAttrs v) && (v ? _secret) && !(v ? __unfix__) then
            "__SECRET_FILE__${toString v._secret}__"
          else
            toString v
        ) value
      )
    else if isAttrs value then
      mapAttrs (_name: processValue) value
    else if isInt value || isFloat value || isString value then
      toString value
    else
      toString value;

  mkSecretOption =
    {
      nullable ? false,
      type ? secretOrStrType,
      default ? null,
      example ? null,
      description,
    }:
    mkOption {
      inherit default;
      type = if nullable then types.nullOr type else type;
      example =
        if example != null then
          example
        else
          literalExpression ''{ _secret = "/run/secrets/secret-file"; }'';
      description = ''
        ${description}
        Can be a plain string (visible in Nix store) or `{ _secret = /path/to/file; }` for file-based secrets.

        !!! warning
            Plain-text secrets will be visible in the Nix store. Use `{ _secret = path; }` for sensitive data.
      '';
    };

  mkJqSecretArgs =
    secretFields:
    let
      processedFields = lib.mapAttrs (
        name: value:
        if value == null then
          {
            flag = "--arg ${name} \"\"";
            ref = "$" + name;
          }
        else if isSecretRef value then
          {
            flag = "--rawfile ${name}Content ${lib.escapeShellArg (toString value._secret)}";
            ref = "($" + name + "Content | rtrimstr(\"\\n\"))";
          }
        else
          {
            flag = "--arg ${name} ${lib.escapeShellArg (toString value)}";
            ref = "$" + name;
          }
      ) secretFields;

      flags = lib.mapAttrsToList (_name: field: field.flag) processedFields;
      refs = lib.mapAttrs (_name: field: field.ref) processedFields;
    in
    {
      inherit refs;
      flagsString = lib.concatStringsSep " " flags;
    };
}
