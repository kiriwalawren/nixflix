{ lib, ... }:
with lib;
let
  util = import ./util.nix { inherit lib; };

  escapeXml =
    str:
    builtins.replaceStrings [ "&" "<" ">" "'" "\"" ] [ "&amp;" "&lt;" "&gt;" "&apos;" "&quot;" ] (
      toString str
    );

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
            tagName = util.toPascalCase name;
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
in
{
  mkXmlContent = tagName: attrs: ''
    <?xml version="1.0" encoding="utf-8"?>
    <${tagName} xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    ${attrsToXml "  " attrs}
    </${tagName}>
  '';
}
