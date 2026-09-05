{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs_22,
  pnpm_10,
  esbuild,
  makeWrapper,
  python313,
  ffmpeg,
  loudgain,
  chromaprint,
}:
let
  pname = "droppedneedle";
  version = "2.12.0";

  src = fetchFromGitHub {
    owner = "DroppedNeedle";
    repo = "DroppedNeedle";
    tag = "v${version}";
    hash = "sha256-Iovi2msVdE/argo4zhY2JQcAgqwfiaQr2BuHC9AKdYM=";
  };

  # frontend/pnpm-lock.yaml pins esbuild 0.27.7 (a transitive Vite dependency);
  # esbuild refuses to run when its JS wrapper version doesn't exactly match
  # the native binary, so nixpkgs' esbuild (a different patch version) can't
  # be substituted as-is via ESBUILD_BINARY_PATH.
  esbuildPinned = esbuild.overrideAttrs (_old: rec {
    version = "0.27.7";
    src = fetchFromGitHub {
      owner = "evanw";
      repo = "esbuild";
      rev = "v${version}";
      hash = "sha256-DsxB7T1EDzaVDG1h0Tc/mEe7moTZJsU7SW7/2gd7h10=";
    };
    vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
  });

  pnpmDeps = fetchPnpmDeps {
    pname = "${pname}-frontend";
    inherit version;
    src = "${src}/frontend";
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-n+Y9fA66YNFolsSZQDM7On8HESZ2Yu+eLAQ0gUXwMXQ=";
  };

  pythonEnv = python313.withPackages (
    ps:
    with ps;
    [
      aiofiles
      bcrypt
      cryptography
      fastapi
      h2
      httpx
      msgspec
      mutagen
      packaging
      pillow
      pydantic
      pydantic-core
      pydantic-settings
      python-dotenv
      python-multipart
      rapidfuzz
      starlette
      unidecode
      uvicorn
    ]
    ++ uvicorn.optional-dependencies.standard
  );
in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmDeps
    ;

  # Exposed so update.sh can resolve the pnpm offline-store hash by building
  # `packages.<system>.droppedneedle.pnpmDeps` in isolation.
  passthru.pnpmDeps = pnpmDeps;

  pnpmRoot = "frontend";

  nativeBuildInputs = [
    nodejs_22
    pnpm_10
    pnpmConfigHook
    esbuildPinned
    makeWrapper
  ];

  postPatch = ''
    # Nix store outputs are read-only. When `configure_frontend_base.py`
    # copies a template file from the nix store, it copies the permissions too.
    # This patch changes the permissions of the copy stage.
    sed -i -e 's/^\( *\)shutil\.copytree(template_root, stage_root, dirs_exist_ok=True)$/\1shutil.copytree(template_root, stage_root, dirs_exist_ok=True)\n\1stage_root.chmod(0o755)\n\1for _p in stage_root.rglob("*"):\n\1    _p.chmod(0o755 if _p.is_dir() else 0o644)/' \
      backend/maintenance/configure_frontend_base.py

    # SvelteKit's `kit.version.name` defaults to `Date.now().toString()`
    # (see https://svelte.dev/docs/kit/configuration#version).
    # This is not deterministic. Let's fix that.
    sed -i "s/kit: {/kit: {\n\t\tversion: { name: '${version}' },/" \
      frontend/svelte.config.js
  '';

  buildPhase = ''
    runHook preBuild

    export ESBUILD_BINARY_PATH=${lib.getExe esbuildPinned}
    export DROPPEDNEEDLE_BASE_PATH_PLACEHOLDER=1

    pushd frontend
    pnpm run build
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/droppedneedle $out/share/droppedneedle $out/bin

    cp -r backend/. $out/lib/droppedneedle/
    cp -r frontend/build $out/share/droppedneedle/static-template

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/droppedneedle \
      --chdir $out/lib/droppedneedle \
      --add-flags "-m maintenance.automatic_upgrade --start-target" \
      --set PYTHONPATH $out/lib/droppedneedle \
      --set DROPPEDNEEDLE_SOURCE_REVISION "${version}" \
      --set COMMIT_TAG "${version}" \
      --prefix PATH : ${
        lib.makeBinPath [
          ffmpeg
          loudgain
          chromaprint
        ]
      }

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/droppedneedle-configure-frontend-base \
      --chdir $out/lib/droppedneedle \
      --add-flags "-m maintenance.configure_frontend_base --template-root $out/share/droppedneedle/static-template" \
      --set PYTHONPATH $out/lib/droppedneedle

    runHook postInstall
  '';

  meta = {
    description = "Music request and discovery app with a built-in native library + download engine";
    homepage = "https://droppedneedle.com/";
    changelog = "https://github.com/DroppedNeedle/DroppedNeedle/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "droppedneedle";
    platforms = lib.platforms.linux;
  };
}
