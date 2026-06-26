final: _prev:
let
  dir = builtins.readDir ./.;
  names = builtins.attrNames dir;

  dirPkgs = builtins.listToAttrs (
    builtins.map
      (name: {
        inherit name;
        value = final.callPackage (./. + "/${name}") { };
      })
      (
        builtins.filter (
          name: dir.${name} == "directory" && builtins.pathExists (./. + "/${name}/default.nix")
        ) names
      )
  );

  filePkgs = builtins.listToAttrs (
    builtins.map
      (name: {
        name = builtins.substring 0 (builtins.stringLength name - 4) name;
        value = final.callPackage (./. + "/${name}") { };
      })
      (
        builtins.filter (
          name: dir.${name} == "regular" && builtins.match ".+\\.nix" name != null && name != "overlay.nix"
        ) names
      )
  );
in
dirPkgs // filePkgs
