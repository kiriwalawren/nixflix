# Renders every systemd unit of the shared syncMode configuration
# (sync-mode-everything.nix) to the text it runs. `src` is the nixflix tree the
# modules came from (seerr-libraries sources a script built outside the unit);
# `evalModules` evaluates a NixOS module list with that tree's modules.
{
  lib,
  pkgs,
  src,
  evalModules,
}:
let
  everything = import ./sync-mode-everything.nix { inherit pkgs lib; };

  evalWith = modules: evalModules ([ everything ] ++ modules);

  plain = builtins.unsafeDiscardStringContext;

  textOf =
    v:
    if builtins.isList v then
      lib.concatMapStringsSep "\n" textOf v
    else if lib.isDerivation v && v ? text then
      v.text
    else if builtins.isString v then
      v
    else
      "";

  # Everything a unit runs that nixflix generates: script, preStart (qBittorrent
  # syncs categories there) and writeShellApplication ExecStarts (maintainerr,
  # recyclarr). seerr-libraries `source`s a separate script, read separately.
  unitText =
    evaluated: name:
    let
      s = evaluated.config.systemd.services.${name};
      sc = s.serviceConfig or { };
    in
    plain (
      lib.concatMapStringsSep "\n" textOf [
        (s.preStart or "")
        (s.script or "")
        (s.postStart or "")
        (sc.ExecStartPre or "")
        (sc.ExecStart or "")
        (sc.ExecStartPost or "")
      ]
    );

  seerrLibrarySyncText =
    evaluated:
    let
      cfg = evaluated.config.nixflix.seerr;
      authUtil = import (src + "/modules/seerr/authUtil.nix") {
        inherit lib cfg;
        inherit (evaluated) pkgs;
      };
    in
    plain
      (import (src + "/modules/seerr/librarySync.nix") {
        inherit lib cfg;
        inherit (evaluated) pkgs;
      } authUtil.curlAuthArgs).text;

  render =
    modules:
    let
      evaluated = evalWith modules;
      inherit (evaluated) config;
      names = builtins.attrNames config.systemd.services;
    in
    {
      inherit config;
      inherit (evaluated) options;
      texts = lib.genAttrs names (unitText evaluated) // {
        seerr-libraries = unitText evaluated "seerr-libraries" + "\n" + seerrLibrarySyncText evaluated;
      };
    };

  # Store paths are blanked so the hash does not depend on the system or on
  # unrelated rebuilds; a changed referenced script must be inlined to count.
  normalize =
    text:
    lib.concatStrings (
      map (x: if builtins.isList x then "/nix/store/HASH-" else x) (
        builtins.split "/nix/store/[a-z0-9]{32}-" text
      )
    );
  hashes = texts: lib.mapAttrs (_: t: builtins.hashString "sha256" (normalize t)) texts;
in
{
  inherit render normalize hashes;
}
