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
    dontUnpack = true;

    dontFixup = true;

    installPhase = ''
      if [ -d "$src" ]; then
        source_root="$src"
      else
        mkdir unpacked
        unzip "$src" -d unpacked
        source_root="unpacked"
      fi

      # Some plugin archives wrap files in a single top-level directory.
      shopt -s nullglob dotglob
      entries=("$source_root"/*)

      if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
        cp -a "''${entries[0]}" "$out"
      else
        mkdir -p "$out"
        cp -a "$source_root"/. "$out/"
      fi
    '';
  }
  // removeAttrs args [
    "pname"
    "version"
    "src"
  ]
)
