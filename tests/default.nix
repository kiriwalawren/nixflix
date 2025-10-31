{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}: {
  # Import all test modules
  vm-tests = import ./vm-tests {inherit system pkgs nixosModules;};
  unit-tests = import ./unit-tests {inherit system pkgs nixosModules;};
}
