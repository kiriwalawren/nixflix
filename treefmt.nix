_: {
  projectRootFile = "flake.nix";
  settings.excludes = [ "**/index.md" ];
  programs.mdformat.enable = true;
  programs.black.enable = true;
  programs.nixfmt.enable = true;
  programs.deadnix.enable = true;
  programs.statix.enable = true;
  programs.yamlfmt.enable = true;
}
