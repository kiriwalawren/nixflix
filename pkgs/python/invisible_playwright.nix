{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # nativeBuildInputs
  gitMinimal,

  # dependencies
  invisible_core,
  playwright,
}:

buildPythonPackage (finalAttrs: {
  pname = "playwright";

  version = "firefox-13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "feder-cr";
    repo = "invisible_playwright";
    tag = "${finalAttrs.version}";
    hash = "sha256-amCEaSZb++lDx3Pmvfmx0WEV7k1oOUy9Jr9HjRBm914=";
  };

  build-system = [
    hatchling
  ];

  nativeBuildInputs = [
    gitMinimal
  ];

  pythonRelaxDeps = [
    "invisible_core"
    "playwright"
  ];
  dependencies = [
    invisible_core
    playwright
  ];

  # Skip tests because they require network access.
  doCheck = false;

  pythonImportsCheck = [ "invisible_playwright" ];

  meta = {
    description = "Anti-Detect Browser that passes every bot detection test. Drop-in Playwright replacement.";
    mainProgram = "invisible_playwright";
    homepage = "https://github.com/feder-cr/invisible_playwright";
    license = lib.licenses.mit;
  };
})
