{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # nativeBuildInputs
  gitMinimal,
  writableTmpDirAsHomeHook,

  # dependencies
  platformdirs,
  requests,
  maxminddb,
  tzdata,
  tqdm,
}:

buildPythonPackage (finalAttrs: {
  pname = "invisible_core";

  # no actual release yet
  version = "352f90c13a9aaef276bdc4bf552d348cd7e15eea";

  pyproject = true;

  src = fetchFromGitHub {
    owner = "feder-cr";
    repo = "invisible_core";
    rev = "${finalAttrs.version}";
    hash = "sha256-BiISHZFI/JStDVFeYXwZkRtthcbiaIe6iuDKFTJNmHs=";
  };

  build-system = [
    hatchling
  ];

  nativeBuildInputs = [
    gitMinimal
    writableTmpDirAsHomeHook
  ];

  dependencies = [
    platformdirs
    requests
    maxminddb
    tzdata
    tqdm
  ];

  doCheck = true;

  pythonImportsCheck = [ "invisible_core" ];

  meta = {
    description = "Anti-Detect Browser that passes every bot detection test. Drop-in Playwright replacement.";
    mainProgram = "invisible_playwright";
    homepage = "https://github.com/feder-cr/invisible_core";
    license = lib.licenses.mit;
  };
})
