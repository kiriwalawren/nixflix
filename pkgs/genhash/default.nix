{pkgs ? import <nixpkgs> {}, ...}:
pkgs.stdenv.mkDerivation rec {
  name = "genhash";
  version = "1.0.0";

  nativeBuildInputs = with pkgs; [
    gcc
    nettle
  ];

  phases = ["buildPhase"];

  buildPhase = ''
    mkdir -p $out/bin
    gcc $src -o $out/bin/${name} -lnettle
  '';

  src = ./pbkdf2-sha512.c;
}
