{
  pkgs,
  lib,
}:
let
  optionsGenerator = import ./generate-options.nix { inherit pkgs lib; };
in
{
  inherit (optionsGenerator) optionsDocs;
  inherit (optionsGenerator) optionsJSON;
  inherit (optionsGenerator) optionsCommonMark;
}
