{ ... }:
{
  projectRootFile = "flake.nix";
  programs.mdformat.enable = true;
  programs.black.enable = true;
  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;
  programs.yamlfmt.enable = true;
}
