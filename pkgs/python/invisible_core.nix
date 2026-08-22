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

buildPythonPackage (_finalAttrs: {
  pname = "invisible_core";
  version = "0.1.0";

  pyproject = true;

  src = fetchFromGitHub {
    owner = "feder-cr";
    repo = "invisible_core";
    rev = "897977f2e21f2c31dd2ef406b54df1ecce25fda1";
    hash = "sha256-dzsrJHVoomipvV0jMqQf3TGJgRid+jUCHT8S7VfsIOA=";
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
