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

buildPythonPackage (_finalAttrs: {
  pname = "invisible_playwright";

  version = "0.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "feder-cr";
    repo = "invisible_playwright";
    rev = "310bb215df207be3a329c80fcfecaed715fdf5f4";
    hash = "sha256-Qq1Oxrtxl2VDwA9k2iSLue3bhxG+5VBh2q3dvHqDao0=";
  };

  build-system = [
    hatchling
  ];

  nativeBuildInputs = [
    gitMinimal
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
