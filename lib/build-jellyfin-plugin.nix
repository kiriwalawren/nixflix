{ pkgs }:
{
  pname,
  version,
  src,
  ...
}@args:
pkgs.stdenvNoCC.mkDerivation (
  {
    inherit pname version src;
    nativeBuildInputs = [ pkgs.unzip ];
    unpackPhase = ''
      mkdir unpacked
      unzip $src -d unpacked
    '';
    dontFixup = true;
    installPhase = ''
      # Handle single-directory zips: if unpacked contains exactly one
      # directory and nothing else, use its contents instead
      shopt -s nullglob dotglob
      entries=(unpacked/*)
      if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
        cp -a "''${entries[0]}" $out
      else
        cp -a unpacked $out
      fi
    '';
  }
  // removeAttrs args [
    "pname"
    "version"
    "src"
  ]
)
