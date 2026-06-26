{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_24,
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
  version = "3.15.3";

  src = fetchFromGitHub {
    owner = "Maintainerr";
    repo = "Maintainerr";
    tag = "v${version}";
    hash = "sha256-SyZ5cJQazTlYfN7dqru6e8fHrqTcejhwpkOcVRdDy5M=";
  };

  offlineCache = yarn-berry_4.fetchYarnBerryDeps {
    inherit src;
    missingHashes = ./missing-hashes.json;
    hash = "sha256-iI3ey9UuVCVU2accnfFaAvzloRrm3JYxnkxuuv4NqG8=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  missingHashes = ./missing-hashes.json;

  nativeBuildInputs = [
    nodejs_24
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
    # Prevents yarn 4.14.1 treating the v8 lockfile as stale and re-resolving from the registry.
    YARN_LOCKFILE_VERSION_OVERRIDE = "8";
  };

  postPatch = ''
    echo 'approvedGitRepositories: ["**"]' >> .yarnrc.yml
    echo 'enableScripts: true' >> .yarnrc.yml
  '';

  preBuild = ''
    awk '/^approvedGitRepositories:/{skip=1;next} skip&&/^[[:space:]]/{next} {skip=0;print}' \
      .yarnrc.yml > .yarnrc.yml.tmp && mv .yarnrc.yml.tmp .yarnrc.yml
  '';

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

    cp -r node_modules $out/lib/maintainerr/

    mkdir -p $out/lib/maintainerr/apps/server
    cp -r apps/server/dist apps/server/package.json \
      $out/lib/maintainerr/apps/server/
    [ -d apps/server/node_modules ] && \
      cp -r apps/server/node_modules $out/lib/maintainerr/apps/server/

    cp -r apps/ui/dist $out/lib/maintainerr/apps/server/dist/ui

    cp -r apps/server/assets $out/lib/maintainerr/apps/server/dist/assets

    mkdir -p $out/lib/maintainerr/packages/contracts
    cp -r packages/contracts/dist packages/contracts/package.json \
      $out/lib/maintainerr/packages/contracts/
    [ -d packages/contracts/node_modules ] && \
      cp -r packages/contracts/node_modules $out/lib/maintainerr/packages/contracts/

    find $out/lib/maintainerr/apps/server/dist/ui -type f \
      -exec sed -i 's,/__PATH_PREFIX__,,g' {} +

    # Replace Docker-specific hardcoded paths with DATA_DIR-aware equivalents.
    sed -i "s|/opt/app/apps/server/dist/database/migrations|$out/lib/maintainerr/apps/server/dist/database/migrations|g" \
      $out/lib/maintainerr/apps/server/dist/app/config/typeOrmConfig.js
    sed -i "s#    ? '/opt/data'#    ? (process.env.DATA_DIR || '/opt/data')#g" \
      $out/lib/maintainerr/apps/server/dist/modules/logging/logs.module.js
    sed -i "s#    ? '/opt/data/logs'#    ? ((process.env.DATA_DIR || '/opt/data') + '/logs')#g" \
      $out/lib/maintainerr/apps/server/dist/modules/logging/logs.controller.js

    makeWrapper ${nodejs_24}/bin/node $out/bin/maintainerr \
      --chdir $out/lib/maintainerr/apps/server \
      --add-flags dist/main.js \
      --set NODE_ENV production \
      --set UV_USE_IO_URING 0 \
      --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]}

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
