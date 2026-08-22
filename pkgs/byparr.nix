{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,

  makeWrapper,

  python3,
  xvfb,
}:

let
  python = python3.withPackages (
    ps: with ps; [
      # dependencies
      fastapi
      invisible_playwright
      playwright
      playwright-captcha # package
      pydantic
      pydantic-settings

      # runtime dependencies
      uvicorn
    ]
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "byparr";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "ThePhaseless";
    repo = "Byparr";
    rev = "ecdd4c112a60c5fb22c781f142537e0b3399e568";
    hash = "sha256-eIbWqbUNOcS0WVgszXPVIbDx0hhRH1d1o+K0JXAEdwY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/{bin,share/byparr-${finalAttrs.version}}
    cp -r * $out/share/byparr-${finalAttrs.version}/.

    makeWrapper ${python}/bin/python $out/bin/byparr \
      --add-flags "$out/share/byparr-${finalAttrs.version}/main.py" \
      --prefix PATH : "${lib.makeBinPath [ xvfb ]}" \
      --prefix LD_LIBRARY_PATH : ${
        pkgs.lib.makeLibraryPath [
          pkgs.gtk3
          pkgs.glib
          pkgs.nss
          pkgs.cairo
          pkgs.pango
          pkgs.cups
          pkgs.dbus
          pkgs.libxcb
          pkgs.libx11
          pkgs.libxcursor
          pkgs.libxi
          pkgs.gcc.cc.lib
          pkgs.alsa-lib
        ]
      }
  '';

  meta = {
    description = "Get your valid antibot cookies yourself! ";
    homepage = "https://github.com/ThePhaseless/Byparr";
    license = lib.licenses.gpl3;
    mainProgram = "byparr";
  };
})
