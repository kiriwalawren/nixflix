{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
import ../lib/mk-reverse-proxy-test.nix {
  inherit system pkgs nixosModules;
  testName = "caddy-integration-test";
  proxyConfig = {
    caddy = {
      enable = true;
      addHostsEntries = true;
    };
  };
}
