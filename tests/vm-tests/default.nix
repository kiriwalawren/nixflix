{
  lib,
  nixosModules,
  pkgs ? import <nixpkgs> {inherit system;},
  system ? builtins.currentSystem,
}: let
  testFiles =
    builtins.filter
    (name: name != "default.nix" && pkgs.lib.hasSuffix ".nix" name)
    (builtins.attrNames (builtins.readDir ./.));

  testNameFromFile = file: pkgs.lib.removeSuffix ".nix" file;

  importTest = file: let
    test = import (./. + "/${file}") {inherit system pkgs nixosModules;};
    fileContents = builtins.readFile (./. + "/${file}");
  in
    test
    // {
      passthru =
        (test.passthru or {})
        // {
          meta =
            (test.passthru.meta or {})
            // {
              requiresNetwork =
                lib.boolToString (builtins.match ".*networking\\.useDHCP[[:space:]]*=[[:space:]]*true.*" fileContents != null);
            };
        };
    };
in
  builtins.listToAttrs (
    map (file: {
      name = testNameFromFile file;
      value = importTest file;
    })
    testFiles
  )
