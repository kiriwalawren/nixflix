{
  lib,
  pkgs,
  jellyfinVersion,
  pluginRepositories,
  plugins,
}:
let
  buildJellyfinPlugin = import ../../lib/build-jellyfin-plugin.nix { inherit pkgs; };
  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };

  normalizeTargetAbi = targetAbi: lib.removeSuffix ".0" targetAbi;

  versionSeries = version: lib.concatStringsSep "." (lib.take 2 (lib.splitVersion version));

  highestByTargetAbi =
    matches:
    if matches == [ ] then
      [ ]
    else
      let
        highestMatch = lib.foldl' (
          best: candidate:
          if
            lib.versionOlder (normalizeTargetAbi best.targetAbi) (normalizeTargetAbi candidate.targetAbi)
          then
            candidate
          else
            best
        ) (lib.head matches) (lib.tail matches);
        highestTargetAbi = normalizeTargetAbi highestMatch.targetAbi;
      in
      lib.filter (match: normalizeTargetAbi match.targetAbi == highestTargetAbi) matches;

  repoPluginDirName = pluginName: pluginVersion: "${pluginName}_${pluginVersion}";

  namedPluginRepositories = lib.mapAttrsToList (
    name: repo: repo // { inherit name; }
  ) pluginRepositories;

  enabledPluginRepositories = lib.filter (repo: repo.enabled) namedPluginRepositories;

  repositoriesWithManifest = map (
    repo:
    repo
    // {
      manifest = builtins.fromJSON (
        builtins.readFile (
          builtins.fetchurl {
            inherit (repo) url;
            sha256 = builtins.convertHash {
              inherit (repo) hash;
              hashAlgo = "sha256";
              toHashFormat = "nix32";
            };
          }
        )
      );
    }
  ) enabledPluginRepositories;

  findPluginSource =
    pluginName: sourceSpec:
    let
      pluginVersion = sourceSpec.version;
      repositoryName = sourceSpec.repository or null;
      matchingRepositories =
        if repositoryName == null then
          repositoriesWithManifest
        else
          lib.filter (repo: repo.name == repositoryName) repositoriesWithManifest;

      versionMatches = lib.concatMap (
        repo:
        lib.concatMap (
          plugin:
          if plugin.name == pluginName then
            map
              (release: {
                inherit (repo) name url;
                inherit (release) sourceUrl version targetAbi;
                timestamp = release.timestamp or "";
                changelog = release.changelog or "";
                guid = plugin.guid or "";
                category = plugin.category or "";
                description = plugin.description or "";
                overview = plugin.overview or "";
                owner = plugin.owner or "";
                imageUrl = plugin.imageUrl or "";
              })
              (
                lib.filter (release: pluginVersion == "latest" || release.version == pluginVersion) (
                  plugin.versions or [ ]
                )
              )
          else
            [ ]
        ) repo.manifest
      ) matchingRepositories;

      matchingAbi = lib.filter (
        match: normalizeTargetAbi match.targetAbi == jellyfinVersion
      ) versionMatches;

      compatibleAbi = lib.filter (
        match:
        let
          normalizedTargetAbi = normalizeTargetAbi match.targetAbi;
        in
        versionSeries normalizedTargetAbi == versionSeries jellyfinVersion
        && !lib.versionOlder jellyfinVersion normalizedTargetAbi
      ) versionMatches;

      selectedMatches = if lib.length matchingAbi == 1 then matchingAbi else versionMatches;

      selectedCompatibleMatches =
        if lib.length matchingAbi > 0 then matchingAbi else highestByTargetAbi compatibleAbi;

      matchingRepositoriesSummary = lib.concatStringsSep ", " (
        lib.unique (map (match: match.name) selectedCompatibleMatches)
      );
    in
    if repositoryName != null && matchingRepositories == [ ] then
      throw "nixflix.jellyfin.plugins.\"${pluginName}\": repository '${repositoryName}' was not found in nixflix.jellyfin.system.pluginRepositories"
    else if versionMatches == [ ] then
      throw "nixflix.jellyfin.plugins.\"${pluginName}\": version '${pluginVersion}' was not found in any configured plugin repository"
    else if selectedCompatibleMatches == [ ] then
      throw "nixflix.jellyfin.plugins.\"${pluginName}\": version '${pluginVersion}' did not have a compatible release for Jellyfin ${jellyfinVersion}"
    else if repositoryName == null && lib.length selectedCompatibleMatches > 1 then
      throw "nixflix.jellyfin.plugins.\"${pluginName}\": version '${pluginVersion}' matched multiple repositories (${matchingRepositoriesSummary}) for Jellyfin ${jellyfinVersion}. Set `package = nixflix.lib.jellyfinPlugins.fromRepo { repository = \"...\"; ...; }` to disambiguate."
    else if lib.length selectedCompatibleMatches == 1 then
      { match = lib.head selectedCompatibleMatches; }
    else if lib.length selectedMatches > 1 then
      throw "nixflix.jellyfin.plugins.\"${pluginName}\": version '${pluginVersion}' matched multiple releases. Add `repository` or update the resolver to disambiguate the target ABI for Jellyfin ${jellyfinVersion}."
    else
      { match = lib.head selectedMatches; };

  packagePluginDirName =
    plugin:
    let
      passthru = plugin.passthru or { };
      version = lib.getVersion plugin;
      name = lib.getName plugin;
    in
    passthru.pluginDirName or (if version == "" then name else "${name}_${version}");

  resolvePluginResult =
    pluginName: pluginCfg:
    if pluginCfg.package == null || lib.isDerivation pluginCfg.package then
      {
        inherit pluginCfg;
      }
    else
      let
        sourceSpec = jellyfinPlugins.fromRepo pluginCfg.package;
        resolution = findPluginSource pluginName sourceSpec;
        resolvedVersion = resolution.match.version;
        pluginDirName = repoPluginDirName pluginName resolvedVersion;
        metaJson =
          pkgs.writeText "jellyfin-plugin-meta-${lib.strings.sanitizeDerivationName pluginName}.json"
            (
              builtins.toJSON {
                inherit (resolution.match) category;
                inherit (resolution.match) changelog;
                inherit (resolution.match) description;
                inherit (resolution.match) guid;
                inherit (resolution.match) imageUrl;
                name = pluginName;
                inherit (resolution.match) overview;
                inherit (resolution.match) owner;
                inherit (resolution.match) targetAbi;
                inherit (resolution.match) timestamp;
                version = resolvedVersion;
              }
            );
      in
      {
        pluginCfg = pluginCfg // {
          package = buildJellyfinPlugin {
            pname = lib.strings.sanitizeDerivationName pluginName;
            version = resolvedVersion;
            src = pkgs.fetchzip {
              url = resolution.match.sourceUrl;
              inherit (sourceSpec) hash;
              stripRoot = false;
            };
            passthru.pluginDirName = pluginDirName;
            postInstall = ''
              cp ${metaJson} $out/meta.json
            '';
          };
        };
      };

  resolvedPluginResults = lib.mapAttrs resolvePluginResult (
    lib.filterAttrs (_name: pluginCfg: pluginCfg.enable) plugins
  );
in
{
  inherit packagePluginDirName repositoriesWithManifest;

  resolvedEnabledPlugins = lib.mapAttrs (_name: result: result.pluginCfg) resolvedPluginResults;

  resolutionWarnings = [ ];
}
