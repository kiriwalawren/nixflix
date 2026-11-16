# Which Jellyfin libraries Seerr enables, as a jq program plus its arguments.
# Kept apart from librarySync.nix so the unit tests can run the exact filter
# against a fixture library list.
{
  lib,
  pkgs,
  cfg,
}:
let
  inherit (cfg.jellyfin) enableAllLibraries libraryFilter excludeLibraries;
in
{
  filter = pkgs.writeText "seerr-library-select.jq" ''
    [ .[]
      | select(($types | length) == 0 or (.type | IN($types[])))
      | select(($names | length) == 0 or (.name | IN($names[])))
      | select(.name | IN($excluded[]) | not)
      | .id ] | join(",")
  '';

  args = lib.escapeShellArgs [
    "--argjson"
    "types"
    (builtins.toJSON (if enableAllLibraries then [ ] else libraryFilter.types))
    "--argjson"
    "names"
    (builtins.toJSON (if enableAllLibraries then [ ] else libraryFilter.names))
    "--argjson"
    "excluded"
    (builtins.toJSON excludeLibraries)
  ];
}
