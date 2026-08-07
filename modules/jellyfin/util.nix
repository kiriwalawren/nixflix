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

  escapeXml =
    str:
    builtins.replaceStrings [ "&" "<" ">" "'" "\"" ] [ "&amp;" "&lt;" "&gt;" "&apos;" "&quot;" ] (
      toString str
    );

  # Nix's toString pads floats to 6 decimals (e.g. 0.5 -> "0.500000"). Trim trailing zeros
  # (and a now-bare trailing '.') so non-integer numeric options render the way Jellyfin's
  # own XML serializer would, without touching the isInt case attrsToXml already handles.
  formatNumber =
    v:
    let
      s = toString v;
    in
    if isInt v then
      s
    else
      let
        m = builtins.match "(-?[0-9]+\\.[0-9]*[1-9])0*" s;
      in
      if m != null then builtins.head m else builtins.head (builtins.match "(-?[0-9]+)\\.0*" s);

  isTaggedStruct = attrs: attrs ? tag && attrs ? content;

  attrsToXml =
    indent: attrs:
    if isTaggedStruct attrs then
      let
        inherit (attrs) content;
        contentStr =
          if isAttrs content then "\n${attrsToXml (indent + "  ") content}${indent}" else escapeXml content;
      in
      "${indent}<${attrs.tag}>${contentStr}</${attrs.tag}>"
    else if isList attrs then
      concatStringsSep "\n" (
        map (
          item:
          if isTaggedStruct item then
            attrsToXml indent item
          else if isAttrs item then
            attrsToXml indent item
          else
            "${indent}<string>${escapeXml item}</string>"
        ) attrs
      )
    else
      concatStringsSep "\n" (
        mapAttrsToList (
          name: value:
          let
            tagName = toPascalCase name;
            valueStr =
              if isBool value then
                (if value then "true" else "false")
              else if isInt value then
                toString value
              else if isList value then
                if value == [ ] then "" else "\n${attrsToXml (indent + "  ") value}${indent}"
              else if isAttrs value then
                if isTaggedStruct value then
                  "\n${attrsToXml (indent + "  ") value}${indent}"
                else
                  "\n${attrsToXml (indent + "  ") value}${indent}"
              else if isFloat value then
                formatNumber value
              else
                escapeXml value;
          in
          if isAttrs value || (isList value && value != [ ]) then
            "${indent}<${tagName}>${valueStr}</${tagName}>"
          else if isList value && value == [ ] then
            "${indent}<${tagName} />"
          else
            "${indent}<${tagName}>${valueStr}</${tagName}>"
        ) attrs
      );

  mkXmlContent = tagName: attrs: ''
    <?xml version="1.0" encoding="utf-8"?>
    <${tagName} xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    ${attrsToXml "  " attrs}
    </${tagName}>
  '';
}
