{lib, ...}:
with lib; rec {
  toPascalCase = str: let
    firstChar = substring 0 1 str;
    rest = substring 1 (-1) str;
  in
    (toUpper firstChar) + rest;

  recursiveTransform = value:
    if isAttrs value
    then
      if value ? tag && value ? content
      then recursiveTransform value.content
      else mapAttrs' (k: v: nameValuePair (toPascalCase k) (recursiveTransform v)) value
    else if isList value
    then map recursiveTransform value
    else value;
}
