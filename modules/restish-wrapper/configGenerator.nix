{lib}: let
  sanitizeVarName = name: lib.replaceStrings ["-"] ["_"] (lib.toUpper name);

  generateConfig = services:
    lib.concatStringsSep ",\n" (lib.mapAttrsToList (name: svc: let
      headerPairs = lib.mapAttrsToList (k: v: ''"${k}": "$HEADER_${sanitizeVarName name}_${sanitizeVarName k}"'') (svc.headers or {});
      queryPairs = lib.mapAttrsToList (k: v: ''"${k}": "$QUERY_${sanitizeVarName name}_${sanitizeVarName k}"'') (svc.query or {});
      profileParts =
        [''"base": "${svc.baseUrl}"'']
        ++ (lib.optionals ((svc.headers or {}) != {}) [''"headers": { ${lib.concatStringsSep ", " headerPairs} }''])
        ++ (lib.optionals ((svc.query or {}) != {}) [''"query": { ${lib.concatStringsSep ", " queryPairs} }'']);
    in ''
      "${name}": {
        "base": "${svc.baseUrl}",
        "profiles": {
          "default": {
    ${lib.concatStringsSep ",\n" profileParts}
          }
        }
      }'') services);
in {
  inherit sanitizeVarName generateConfig;
}
