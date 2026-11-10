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

  # Generated files a unit refers to (jellyfin-auth, radarr-names.json,
  # categories.json, an ExecStartPre script, ...) must count as part of the
  # unit, but their contents are not readable here: pure evaluation reads no
  # .drv, and building them would be import-from-derivation. So, for this
  # render only, every generated text file (writeText, writeShellScript,
  # writeScript, writeTextFile) gets a hash of its normalized text appended to
  # its name. A unit that refers to the file then changes when its content
  # does, nested references included, on every system.
  contentNamed =
    name: text:
    "${name}-c${builtins.substring 0 16 (builtins.hashString "sha256" (normalize (plain text)))}";
  # trivial-builders' writers call their own writeTextFile, so each writer
  # nixflix (and the NixOS modules it configures) uses is wrapped.
  contentNamedTextFiles = _final: prev: {
    writeTextFile =
      args: prev.writeTextFile (args // { name = contentNamed args.name (args.text or ""); });
    writeText = name: text: prev.writeText (contentNamed name text) text;
    writeScript = name: text: prev.writeScript (contentNamed name text) text;
    writeShellScript = name: text: prev.writeShellScript (contentNamed name text) text;
  };

  evalWith =
    modules:
    evalModules (
      [
        everything
        { nixpkgs.overlays = [ contentNamedTextFiles ]; }
      ]
      ++ modules
    );

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
  # The text keeps its string context: the derivations it references.
  unitTextWithContext =
    evaluated: name:
    let
      s = evaluated.config.systemd.services.${name};
      sc = s.serviceConfig or { };
    in
    lib.concatMapStringsSep "\n" textOf [
      (s.preStart or "")
      (s.script or "")
      (s.postStart or "")
      (sc.ExecStartPre or "")
      (sc.ExecStart or "")
      (sc.ExecStartPost or "")
    ];
  unitText = evaluated: name: plain (unitTextWithContext evaluated name);

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

  # Store-path hashes and the system name are blanked so a hash is the same on
  # every system and unaffected by unrelated rebuilds.
  normalize =
    text:
    builtins.replaceStrings [ "x86_64-linux" "aarch64-linux" ] [ "SYSTEM" "SYSTEM" ] (
      lib.concatStrings (
        map (x: if builtins.isList x then "/nix/store/HASH-" else x) (
          builtins.split "/nix/store/[a-z0-9]{32}-" text
        )
      )
    );

  hashes = rendered: lib.mapAttrs (_: t: builtins.hashString "sha256" (normalize t)) rendered.texts;
in
{
  inherit render normalize hashes;
}
