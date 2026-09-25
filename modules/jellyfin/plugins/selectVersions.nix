{
  lib,
  jellyfinVersion,
  relaxVersionCheck ? false,
}:
let
  # Target abi is always 4 components long, and Jellyfin Version needs to be the same length,
  # or versionAtLeast will return `false` despite the only difference in versions being the
  # number of segments.
  normalizedJellyfinVersion = lib.versions.pad 4 jellyfinVersion;

  versionFilter =
    version:
    # Basic check that Jellyfin version is equal to or greater than the target ABI,as done in
    # Jellyfin: https://github.com/jellyfin/jellyfin/blob/208c278b75abd897aefa1e1175126eac5e4dbfaa/Emby.Server.Implementations/Updates/InstallationManager.cs#L269-L271
    (lib.strings.versionAtLeast normalizedJellyfinVersion version.targetAbi)
    # In addition, if the version is 12 or later, then the target ABI must be too, as Jellyfin
    # on their blog said that "plugins built for 10.11 will not load on 12.0 and need updated
    # builds from their authors" (i.e. target abi >=12):
    # https://jellyfin.org/posts/jellyfin-release-12.0#tl-dr
    && (
      lib.strings.versionOlder normalizedJellyfinVersion "12"
      || lib.strings.versionAtLeast version.targetAbi "12"
      # Or bypass this check if relaxed.
      || relaxVersionCheck
    );
in
versions:
let
  filteredVersions = builtins.sort (x: y: lib.strings.versionOlder x.version y.version) (
    builtins.filter versionFilter versions
  );
in
filteredVersions
