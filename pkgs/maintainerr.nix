{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  yarn-berry_4,
  makeWrapper,
  python3,
  pkg-config,
  node-gyp,
  sqlite,
  cairo,
  pango,
  libjpeg,
  giflib,
  pixman,
  librsvg,
}:
let
  pname = "maintainerr";
  version = "3.13.0";

  src = fetchFromGitHub {
    owner = "Maintainerr";
    repo = "Maintainerr";
    tag = "v${version}";
    hash = lib.fakeHash;
  };

  offlineCache = yarn-berry_4.fetchYarnBerryDeps {
    inherit src;
    hash = lib.fakeHash;
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    nodejs_22
    yarn-berry_4
    yarn-berry_4.yarnBerryConfigHook
    makeWrapper
    python3
    pkg-config
    node-gyp
  ];

  buildInputs = [
    sqlite
    cairo
    pango
    libjpeg
    giflib
    pixman
    librsvg
  ];

  env = {
    PYTHON = "${python3}/bin/python3";
    npm_config_sqlite = "${sqlite.dev}";
    inherit offlineCache;
  };

  buildPhase = ''
    runHook preBuild
    echo "VITE_BASE_PATH=/__PATH_PREFIX__" >> apps/ui/.env
    yarn turbo build
    yarn workspaces focus --all --production
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/maintainerr $out/bin

    # root node_modules (hoisted dependencies)
    cp -r node_modules $out/lib/maintainerr/

    # server: compiled output, package manifest, local node_modules
    mkdir -p $out/lib/maintainerr/apps/server
    cp -r apps/server/dist apps/server/package.json apps/server/node_modules \
      $out/lib/maintainerr/apps/server/

    # UI output served statically by the server (mirrors Docker layout)
    cp -r apps/ui/dist $out/lib/maintainerr/apps/server/dist/ui

    # bundled fonts/images for overlay rendering
    cp -r apps/server/assets $out/lib/maintainerr/apps/server/dist/assets

    # contracts package
    mkdir -p $out/lib/maintainerr/packages/contracts
    cp -r packages/contracts/dist packages/contracts/package.json \
      packages/contracts/node_modules \
      $out/lib/maintainerr/packages/contracts/

    # Replace the build-time placeholder with an empty base path.
    # The Nix store is immutable so this must happen at build time rather
    # than at service startup (as Docker's start.sh would do).
    find $out/lib/maintainerr/apps/server/dist/ui -type f \
      -exec sed -i 's,/__PATH_PREFIX__,,g' {} +

    makeWrapper ${nodejs_22}/bin/node $out/bin/maintainerr \
      --chdir $out/lib/maintainerr/apps/server \
      --add-flags dist/main.js \
      --set NODE_ENV production \
      --set UV_USE_IO_URING 0 \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}

    runHook postInstall
  '';

  meta = {
    description = "Rules-based media library maintenance tool for Plex/Jellyfin";
    homepage = "https://github.com/Maintainerr/Maintainerr";
    changelog = "https://github.com/Maintainerr/Maintainerr/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "maintainerr";
    platforms = lib.platforms.linux;
  };
}
