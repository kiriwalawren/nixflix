{ lib }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (secrets) isSecretRef;

  toIniValue =
    value:
    if isSecretRef value then
      "__SECRET_FILE__${toString value._secret}__"
    else if isBool value then
      if value then "1" else "0"
    else if isList value then
      concatStringsSep ", " (map toIniValue value)
    else if isString value || isInt value || isFloat value then
      toString value
    else
      toString value;

  generateKeyValue = key: value: "${key} = ${toIniValue value}";

  generateSubsection =
    name: attrs:
    let
      fields = mapAttrsToList generateKeyValue attrs;
    in
    ''
      [[${name}]]
      ${concatStringsSep "\n" fields}
    '';

  generateMiscSection =
    miscSettings:
    let
      fields = mapAttrsToList generateKeyValue miscSettings;
    in
    ''
      [misc]
      ${concatStringsSep "\n" fields}
    '';

  generateServersSection =
    servers:
    if servers == [ ] || servers == null then
      ""
    else
      ''
        [servers]
        ${concatStringsSep "\n" (map (srv: generateSubsection srv.name srv) servers)}
      '';

  generateCategoriesSection =
    categories:
    if categories == [ ] || categories == null then
      ""
    else
      ''
        [categories]
        ${concatStringsSep "\n" (map (cat: generateSubsection cat.name cat) categories)}
      '';

  generatePrefixedSection =
    sectionName: settings:
    if settings == { } || settings == null then
      ""
    else
      let
        prefixedFields = mapAttrsToList (
          key: value: "${sectionName}_${key} = ${toIniValue value}"
        ) settings;
      in
      ''
        [${sectionName}]
        ${concatStringsSep "\n" prefixedFields}
      '';

  prefixedSections = [
    "ncenter"
    "acenter"
    "ntfosd"
    "prowl"
    "pushover"
    "pushbullet"
    "apprise"
    "nscript"
  ];

  generateSabnzbdIni =
    settings:
    let
      miscSection = generateMiscSection (settings.misc or { });
      serversSection = generateServersSection (settings.servers or [ ]);
      categoriesSection = generateCategoriesSection (settings.categories or [ ]);
      prefixedSects = map (name: generatePrefixedSection name (settings.${name} or { })) prefixedSections;
      allSections = [
        miscSection
        serversSection
        categoriesSection
      ]
      ++ prefixedSects;
    in
    concatStringsSep "\n\n" (filter (s: s != "") allSections);
in
{
  inherit generateSabnzbdIni;
}
