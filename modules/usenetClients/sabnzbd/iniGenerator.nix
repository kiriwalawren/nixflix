{ lib }:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (secrets) isSecretRef;

  # A list item. Secrets get mergeSecrets.py's list-safe marker: its default
  # triple-quoting does not parse inside a ConfigObj list.
  toIniListItem =
    value:
    if isSecretRef value then "__SECRET_LIST_ITEM__${toString value._secret}__" else toIniValue value;

  toIniValue =
    value:
    if isSecretRef value then
      "__SECRET_FILE__${toString value._secret}__"
    else if isBool value then
      if value then "1" else "0"
    else if isList value then
      concatStringsSep ", " (map toIniListItem value)
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

  # A string ConfigObj reads back verbatim, whatever it contains (commas,
  # `#`, `=`, one kind of quote). Plain list items above stay unquoted, as
  # before; RSS values are URLs and regexes, so they are always quoted.
  quoteIni =
    s:
    if hasInfix "\n" s then
      throw "nixflix.usenetClients.sabnzbd.settings.rss: value contains a newline: ${s}"
    else if !(hasInfix "\"" s) then
      "\"${s}\""
    else if !(hasInfix "'" s) then
      "'${s}'"
    else
      throw "nixflix.usenetClients.sabnzbd.settings.rss: value contains both quote characters: ${s}";

  rssItem = value: if isSecretRef value then toIniListItem value else quoteIni (toString value);

  # Always a ConfigObj LIST (a single item gets a trailing comma): SABnzbd's
  # OptionList re-splits a plain string on commas, breaking a URL that has
  # one in its query string.
  rssList =
    values: concatStringsSep ", " (map rssItem values) + optionalString (length values == 1) ",";

  generateRssFeed =
    feed:
    let
      extra = removeAttrs feed [
        "name"
        "uri"
        "cat"
        "pp"
        "script"
        "enable"
        "priority"
        "filters"
      ];
      filterLine =
        n: f:
        "filter${toString n} = ${
          rssList [
            f.category
            f.pp
            f.script
            f.type
            f.match
            (toString f.priority)
            (if f.enable then "1" else "0")
          ]
        }";
    in
    ''
      [[${feed.name}]]
      name = ${quoteIni feed.name}
      uri = ${rssList feed.uri}
      cat = ${quoteIni feed.cat}
      pp = ${quoteIni (toString feed.pp)}
      script = ${quoteIni feed.script}
      enable = ${toIniValue feed.enable}
      priority = ${toString feed.priority}
      ${concatStringsSep "\n" (imap0 filterLine feed.filters)}
      ${concatStringsSep "\n" (mapAttrsToList generateKeyValue extra)}
    '';

  generateRssSection =
    feeds:
    if feeds == [ ] || feeds == null then
      ""
    else
      ''
        [rss]
        ${concatStringsSep "\n" (map generateRssFeed feeds)}
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
      rssSection = generateRssSection (settings.rss or [ ]);
      prefixedSects = map (name: generatePrefixedSection name (settings.${name} or { })) prefixedSections;
      allSections = [
        miscSection
        serversSection
        categoriesSection
        rssSection
      ]
      ++ prefixedSects;
    in
    concatStringsSep "\n\n" (filter (s: s != "") allSections);
in
{
  inherit generateSabnzbdIni;
}
