{ lib, jellyfinVersion }:
let
  # Target abi is always 4 components long, and Jellyfin Version needs to be the same length,
  # or versionAtLeast will return `false` despite the only difference in versions being the
  # number of segments.
  normalizedJellyfinVersion = lib.versions.pad 4 jellyfinVersion;

  versionFilter = version: lib.strings.versionAtLeast normalizedJellyfinVersion version.targetAbi;
in
versions:
let
  filteredVersions = builtins.sort (x: y: lib.strings.versionOlder x.version y.version) (
    builtins.filter versionFilter versions
  );
in
filteredVersions
