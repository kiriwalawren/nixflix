{
  system,
  pkgs,
  lib,
  nixosModules,
}:
let
  helpers = import ../lib/unit-test-helpers.nix { inherit system pkgs nixosModules; };

  testFiles = builtins.filter (name: name != "default.nix" && lib.hasSuffix ".nix" name) (
    builtins.attrNames (builtins.readDir ./.)
  );

  importTests =
    file:
    import (./. + "/${file}") (
      {
        inherit
          system
          pkgs
          lib
          nixosModules
          ;
      }
      // helpers
    );

  mergeUnique = lib.foldl' (
    acc: tests:
    let
      dupes = builtins.attrNames (builtins.intersectAttrs acc tests);
    in
    if dupes != [ ] then
      throw "duplicate unit test names: ${lib.concatStringsSep ", " dupes}"
    else
      acc // tests
  ) { };
in
mergeUnique (map importTests testFiles)
