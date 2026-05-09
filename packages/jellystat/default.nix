{
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_20,
  makeWrapper,
  lib,
}:
let
  version = "1.1.10";
in
buildNpmPackage {
  inherit version;
  pname = "jellystat";

  src = fetchFromGitHub {
    owner = "CyferShepard";
    repo = "Jellystat";
    rev = version;
    hash = "sha256-eMDnQJLGEUlOZupUODXvNQ/TtQyQ7salqeZatR6ieRQ=";
  };

  npmDepsHash = "sha256-Y40ZnpHjEbYOjDrgwjLxCTyGWHGH6Zw8JADUiJc4hl4=";
  npmFlags = [
    "--legacy-peer-deps"
    "--ignore-scripts"
  ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/jellystat/backend $out/lib/jellystat/dist $out/bin

    cp package.json $out/lib/jellystat/package.json
    cp -r backend/. $out/lib/jellystat/backend/
    cp -r node_modules $out/lib/jellystat/backend/node_modules
    cp -r dist/. $out/lib/jellystat/dist/

    makeWrapper ${nodejs_20}/bin/node $out/bin/jellystat \
      --chdir $out/lib/jellystat/backend \
      --add-flags "server.js"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Free and open source statistics App for Jellyfin";
    longDescription = ''
      Jellystat is a free and open source statistics App for Jellyfin that
      provides session monitoring, watch history, library statistics, and
      user activity tracking.
    '';
    homepage = "https://github.com/CyferShepard/Jellystat";
    license = licenses.gpl3;
    mainProgram = "jellystat";
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
