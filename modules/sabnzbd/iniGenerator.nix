{ lib, pkgs }:
with lib;
let
  valueOrSecret = import ./valueOrSecretType.nix { inherit lib; };
  inherit (valueOrSecret) isSecretRef processValue;

  toIniValue = value:
    if isSecretRef value then
      processValue value
    else if isBool value then
      if value then "1" else "0"
    else if isList value then
      concatStringsSep ", " (map toIniValue value)
    else if isString value || isInt value || isFloat value then
      toString value
    else
      toString value;

  generateKeyValue = key: value:
    "${key} = ${toIniValue value}";

  generateSubsection = name: attrs:
    let
      fields = mapAttrsToList generateKeyValue (filterAttrs (n: _v: n != "name") attrs);
    in
    ''
      [[${name}]]
      ${concatStringsSep "\n" fields}
    '';

  generateMiscSection = settings:
    let
      miscAttrs = filterAttrs (n: _v: n != "servers" && n != "categories") settings;
      fields = mapAttrsToList generateKeyValue miscAttrs;
    in
    ''
      [misc]
      ${concatStringsSep "\n" fields}
    '';

  generateServersSection = servers:
    if servers == [] || servers == null then ""
    else
    ''
      [servers]
      ${concatStringsSep "\n" (map (srv: generateSubsection srv.name srv) servers)}
    '';

  generateCategoriesSection = categories:
    if categories == [] || categories == null then ""
    else
    ''
      [categories]
      ${concatStringsSep "\n" (map (cat: generateSubsection cat.name cat) categories)}
    '';

  generateSabnzbdIni = settings:
    let
      miscSection = generateMiscSection settings;
      serversSection = generateServersSection (settings.servers or []);
      categoriesSection = generateCategoriesSection (settings.categories or []);
    in
    concatStringsSep "\n\n" (filter (s: s != "") [miscSection serversSection categoriesSection]);

in
{
  inherit generateSabnzbdIni;
}
