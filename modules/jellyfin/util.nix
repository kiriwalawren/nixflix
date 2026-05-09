{ lib, ... }:
with lib;
rec {
  # Nix option names whose PascalCase form requires special handling
  # (e.g. acronyms where naive first-char uppercasing is insufficient).
  pascalCaseOverrides = {
    uiCulture = "UICulture";
  };

  toPascalCase =
    str:
    pascalCaseOverrides.${str} or (
      let
        firstChar = substring 0 1 str;
        rest = substring 1 (-1) str;
      in
      (toUpper firstChar) + rest
    );

  recursiveTransform =
    value:
    if isAttrs value then
      mapAttrs' (k: v: nameValuePair (toPascalCase k) (recursiveTransform v)) value
    else if isList value then
      map recursiveTransform value
    else
      value;
}
