{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}: let
  # Get all .nix files in the current directory except default.nix
  testFiles =
    builtins.filter
    (name: name != "default.nix" && pkgs.lib.hasSuffix ".nix" name)
    (builtins.attrNames (builtins.readDir ./.));

  # Convert filename to test name (e.g., "sonarr-basic.nix" -> "sonarr-basic")
  testNameFromFile = file: pkgs.lib.removeSuffix ".nix" file;

  # Import each test file with the required arguments
  importTest = file: import (./. + "/${file}") {inherit system pkgs nixosModules;};
in
  # Create an attribute set of all tests
  builtins.listToAttrs (
    map (file: {
      name = testNameFromFile file;
      value = importTest file;
    })
    testFiles
  )
