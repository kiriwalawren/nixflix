{ lib }:
let
  toNix = v: lib.generators.toPretty { } v;

  # Literal `(objExpr).${"fieldName"}` text -- safe for any field name, valid identifier or not.
  accessExpr = objExpr: fieldName: "(${objExpr}).\${" + toNix fieldName + "}";

  zeroValueFor =
    schema:
    if schema.type or null == "string" then
      ""
    else if schema.type or null == "integer" then
      0
    else if schema.type or null == "boolean" then
      false
    else if schema.type or null == "array" then
      [ ]
    else
      { };

  enumConsts =
    schema:
    if (schema.enum or null) != null then
      schema.enum
    else if (schema.oneOf or null) != null && lib.all (o: o ? const) schema.oneOf then
      map (o: o.const) schema.oneOf
    else
      null;

  enumDescriptionSuffix =
    schema:
    if (schema.oneOf or null) != null && lib.all (o: o ? const && o ? title) schema.oneOf then
      "\n\nOne of: " + lib.concatMapStringsSep ", " (o: "`${o.const}` (${o.title})") schema.oneOf
    else
      "";

  mkDescription =
    schema:
    let
      parts = lib.filter (s: s != null && s != "") [
        (schema.title or null)
        ((schema.description or "") + enumDescriptionSuffix schema)
      ];
    in
    if parts == [ ] then null else lib.concatStringsSep "\n\n" parts;

  mkDescriptionAttr =
    schema:
    let
      d = mkDescription schema;
    in
    lib.optionalString (d != null) "description = ${toNix d};";

  # Nix type-expression text for a scalar/enum schema node, or null (caller falls back to freeform).
  primitiveTypeText =
    schema:
    if (enumConsts schema) != null then
      "lib.types.enum ${toNix (enumConsts schema)}"
    else if schema.type or null == "string" then
      "lib.types.str"
    else if schema.type or null == "integer" && ((schema ? minimum) || (schema ? maximum)) then
      "(lib.types.ints.between ${toNix (schema.minimum or (-1000000000000))} ${
        toNix (schema.maximum or 1000000000000)
      })"
    else if schema.type or null == "integer" then
      "lib.types.int"
    else if schema.type or null == "boolean" then
      "lib.types.bool"
    else
      null;

  # A single `{ if; then; }` node, bare or as one `allOf` entry (the more common real-world idiom).
  mkIfThenRule =
    node:
    if
      (node."if".properties or null) != null
      && lib.length (lib.attrNames node."if".properties) == 1
      && (node."then".required or null) != null
    then
      let
        field = lib.head (lib.attrNames node."if".properties);
      in
      {
        inherit field;
        branches = [
          {
            value = node."if".properties.${field}.const or null;
            required = node."then".required;
          }
        ];
      }
    else
      null;

  # { field, branches = [ { value, required } ... ]; } or null if unrecognized (falls through to unenforced).
  mkConditionalRule =
    schema:
    if (mkIfThenRule schema) != null then
      mkIfThenRule schema
    else if (schema.allOf or null) != null && lib.any (el: (mkIfThenRule el) != null) schema.allOf then
      mkIfThenRule (lib.findFirst (el: (mkIfThenRule el) != null) null schema.allOf)
    else if
      (schema.anyOf or null) != null
      && lib.all (
        b: lib.length (lib.attrNames (b.properties or { })) >= 1 && (b.required or null) != null
      ) schema.anyOf
      && (
        let
          fs = map (b: lib.head (lib.attrNames b.properties)) schema.anyOf;
        in
        lib.all (f: f == lib.head fs) fs
      )
    then
      let
        field = lib.head (lib.attrNames (lib.head schema.anyOf).properties);
      in
      {
        inherit field;
        branches = map (b: {
          value = b.properties.${field}.const or null;
          inherit (b) required;
        }) schema.anyOf;
      }
    else
      null;

  # Field names made conditionally-required anywhere in this object schema's own rule.
  conditionallyRequiredFields =
    schema:
    let
      rule = mkConditionalRule schema;
    in
    if rule == null then [ ] else lib.concatMap (b: b.required) rule.branches;

  # `lib.mkOption {...}` text for one schema node; `nullable` fields get `nullOr`/`null` default.
  mkOptionText =
    schema: nullable:
    let
      isArrayOfObjects = schema.type or null == "array" && (schema.items.type or null) == "object";
      isArrayOfPrimitives =
        schema.type or null == "array" && (primitiveTypeText (schema.items or { })) != null;
      isPrimitive = (primitiveTypeText schema) != null;

      coreTypeText =
        if isArrayOfObjects then
          let
            childNullable = conditionallyRequiredFields schema.items;
          in
          "lib.types.listOf (lib.types.submodule { options = { ${mkObjectOptionsBody schema.items childNullable} }; })"
        else if isArrayOfPrimitives then
          "lib.types.listOf (${primitiveTypeText schema.items})"
        else if isPrimitive then
          primitiveTypeText schema
        else
          null;

      coreDefaultText = toNix (schema.default or (zeroValueFor schema));
    in
    if coreTypeText == null then
      ''
        lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = ${toNix (schema.default or { })};
          description = ${toNix ''
            Freeform passthrough: this field's JSON-Schema shape was not recognized by
            schemaToOptions.nix. Set keys directly; they pass through verbatim. Original
            schema: ${builtins.toJSON schema}
          ''};
        }''
    else
      ''
        lib.mkOption {
          type = ${if nullable then "(lib.types.nullOr (${coreTypeText}))" else coreTypeText};
          default = ${if nullable then "null" else coreDefaultText};
          ${mkDescriptionAttr schema}
        }'';

  mkObjectOptionsBody =
    schema: nullableFields:
    let
      props = schema.properties or { };
    in
    lib.concatMapStringsSep "\n" (
      name: "${toNix name} = ${mkOptionText props.${name} (lib.elem name nullableFields)};"
    ) (lib.attrNames props);

  mkAssertionEntry =
    objExpr: field: branchValue: requiredField:
    let
      fieldAccess = accessExpr objExpr field;
      requiredAccess = accessExpr objExpr requiredField;
      msg = "when `${field}` is ${builtins.toJSON branchValue}, `${requiredField}` must be set";
    in
    "{ assertion = ${fieldAccess} != ${toNix branchValue} || ${requiredAccess} != null; message = ${toNix msg}; }";

  # Live Nix expression text (a list of { assertion; message; }), never a toNix'd value.
  mkAssertionsText =
    objExpr: schema:
    let
      rule = mkConditionalRule schema;
      ownEntries =
        if rule == null then
          [ ]
        else
          lib.concatMap (
            branch: map (reqField: mkAssertionEntry objExpr rule.field branch.value reqField) branch.required
          ) rule.branches;
      ownText = "[ " + lib.concatStringsSep " " ownEntries + " ]";

      props = schema.properties or { };
      childTexts = lib.concatMapStringsSep " ++ " (
        propName:
        let
          propSchema = props.${propName};
        in
        if propSchema.type or null == "array" && (propSchema.items.type or null) == "object" then
          let
            itemAssertions = mkAssertionsText "item" propSchema.items;
            listAccess = accessExpr objExpr propName;
          in
          # Guarded: a conditionally-required (nullable) array-of-objects field may be unset.
          "(let v = ${listAccess}; in if v == null then [ ] else lib.concatLists (lib.imap0 (i: item: ${itemAssertions}) v))"
        else
          "[ ]"
      ) (lib.attrNames props);
      childTextsFull = if props == { } then "[ ]" else "(${childTexts})";
    in
    "(${ownText} ++ ${childTextsFull})";

  # Pure codegen output only: config option type/description + mkAssertions (no package/apiId).
  mkPluginFile =
    {
      pluginName,
      pluginId,
      schema,
      description,
    }:
    let
      topNullable = conditionallyRequiredFields schema;
    in
    ''
      # DO NOT EDIT BY HAND -- generated by update.sh from "${pluginName}"'s manifest.json.
      # Discovered api id (its .ndp bundle name): ${pluginId} -- check default.nix's apiId matches.
      { lib }:
      {
        type = lib.types.submodule {
          options = {
            ${mkObjectOptionsBody schema topNullable}
          };
        };
        description = ${toNix description};
        mkAssertions = cfg: ${mkAssertionsText "cfg" schema};
      }
    '';
in
{
  inherit
    mkOptionText
    mkObjectOptionsBody
    mkPluginFile
    mkConditionalRule
    mkAssertionsText
    ;
}
