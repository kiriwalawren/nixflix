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
      # Derivations each unit's text references (scripts, JSON and config
      # files it reads, packages), as .drv paths.
      refs = lib.genAttrs names (
        n: builtins.attrNames (builtins.getContext (unitTextWithContext evaluated n))
      );
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

  # Generated files a unit refers to (jellyfin-auth, radarr-names.json,
  # categories.json, an ExecStartPre script, ...) count as part of the unit:
  # every referenced text-file derivation (writeText, writeShellScript, ...;
  # its .drv carries a `text` attribute) is read from its .drv, and so are
  # the text files those reference. Packages and stdenv are not followed.
  isTextDrv = drv: lib.hasInfix "\\\"text\\\":" drv || lib.hasInfix "(\"text\"," drv;
  inputDrvs =
    drv:
    map builtins.head (
      builtins.filter builtins.isList (
        builtins.split "\\(\"(/nix/store/[a-z0-9]{32}-[^\"]+\\.drv)\"," drv
      )
    );
  textFiles =
    roots:
    map (i: normalize i.drv) (
      builtins.filter (i: isTextDrv i.drv) (
        builtins.genericClosure {
          startSet = map (key: {
            inherit key;
            drv = builtins.readFile key;
          }) roots;
          operator =
            item:
            let
              text = isTextDrv item.drv;
            in
            lib.optionals text (
              map (key: {
                inherit key;
                drv = builtins.readFile key;
              }) (inputDrvs item.drv)
            );
        }
      )
    );
  hashes =
    rendered:
    lib.mapAttrs (
      n: t:
      builtins.hashString "sha256" (
        lib.concatStringsSep "\n--- referenced file\n" (
          [ (normalize t) ] ++ lib.sort lib.lessThan (textFiles (rendered.refs.${n} or [ ]))
        )
      )
    ) rendered.texts;
in
{
  inherit
    render
    normalize
    hashes
    textFiles
    ;
}
