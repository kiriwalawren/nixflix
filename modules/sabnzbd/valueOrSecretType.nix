{ lib }:
with lib;
let
  isSecretRef = value:
    (builtins.isAttrs value) && (value ? _secret) && !(value ? __unfix__);

  processValue = value:
    if isSecretRef value then
      "__SECRET_FILE__${toString value._secret}__"
    else if isBool value then
      if value then "1" else "0"
    else if isList value then
      concatStringsSep ", " (map processValue value)
    else if isAttrs value then
      mapAttrs (_name: processValue) value
    else if isInt value || isFloat value || isString value then
      toString value
    else
      toString value;

in
{
  inherit isSecretRef processValue;
}
