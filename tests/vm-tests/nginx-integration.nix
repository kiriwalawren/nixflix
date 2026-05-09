{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
import ../lib/mk-reverse-proxy-test.nix {
  inherit system pkgs nixosModules;
  testName = "nginx-integration-test";
  proxyConfig = {
    nginx = {
      enable = true;
      addHostsEntries = true;
    };
  };
}
