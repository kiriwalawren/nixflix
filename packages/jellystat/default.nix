{
  stdenv,
  fetchFromGitHub,
  nodejs_20,
  python3,
  makeWrapper,
  jq,
  curl,
  postgresql,
  cacert,
  writeTextFile,
  lib,
}:
let
  pname = "jellystat";
  version = "1.1.8";

  src = fetchFromGitHub {
    owner = "CyferShepard";
    repo = "Jellystat";
    rev = "V${version}";
    sha256 = "sha256-KQJR+xw0xHsfLvnpSupT6GHsVHY9LXFqH0f3xqoP9q8=";
  };

in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    nodejs_20
    python3
    makeWrapper
  ];

  buildInputs = [
    postgresql
    jq
    curl
  ];

  setSSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  configurePhase = ''
    export HOME=$TMPDIR
  '';

  buildPhase = ''
    runHook preBuild

    cd backend
    npm install --ignore-scripts --legacy-peer-deps

    cd ..
    npm install --ignore-scripts --legacy-peer-deps
    npm run build --ignore-scripts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/jellystat/backend
    mkdir -p $out/lib/jellystat/dist
    mkdir -p $out/bin

    cp -r backend/* $out/lib/jellystat/backend/
    cp -r dist/* $out/lib/jellystat/dist/ 2>/dev/null || true

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
    maintainers = [];
    platforms = platforms.linux;
  };
}
