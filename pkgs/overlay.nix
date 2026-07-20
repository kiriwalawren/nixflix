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
dirPkgs
// filePkgs
// {
  pythonPackagesExtensions = _prev.pythonPackagesExtensions ++ [
    (pyFinal: _pyPrev: {
      invisible_core = pyFinal.callPackage ./python/invisible_core.nix { };
      invisible_playwright = pyFinal.callPackage ./python/invisible_playwright.nix { };
      playwright-captcha = pyFinal.callPackage ./python/playwright-captcha.nix { };
      twocaptcha_async = pyFinal.callPackage ./python/2captcha-python-async.nix { };
    })
  ];
}
