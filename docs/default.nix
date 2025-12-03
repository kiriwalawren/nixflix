{pkgs, ...}: let
  docsGenerator = import ./generator {
    inherit pkgs;
    inherit (pkgs) lib;
  };

  pythonEnv = pkgs.python3.withPackages (ps:
    with ps; [
      mkdocs-material
      mkdocs-minify-plugin
      mkdocs-git-revision-date-localized-plugin
      pymdown-extensions
      pygments
    ]);
in {
  docs = pkgs.stdenv.mkDerivation {
    name = "nixflix-docs";
    src = ../.;

    nativeBuildInputs = [pythonEnv];

    buildPhase = ''
      echo "Generating option documentation..."
      cp -r ${docsGenerator.optionsDocs}/reference/* docs/reference/

      echo "Replacing README placeholder..."
      sed -i '/# README_PLACEHOLDER/r README.md' docs/index.md
      sed -i '/# README_PLACEHOLDER/d' docs/index.md

      echo "Merging navigation..."
      ${pkgs.python3}/bin/python3 ${./generator/merge-nav.py} \
        docs/mkdocs.base.yml \
        ${docsGenerator.optionsDocs}/reference/nav.yml \
        mkdocs.yml

      echo "Building mkdocs site..."
      ${pythonEnv}/bin/mkdocs build -d $out

      rm -rf $out/generator
      rm $out/mkdocs.base.yml
      rm $out/default.nix
    '';

    installPhase = ''
      echo "Documentation built at $out"
    '';
  };

  docs-options = docsGenerator.optionsDocs;
}
