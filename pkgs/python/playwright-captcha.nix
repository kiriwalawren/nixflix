{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  twocaptcha_async,
  playwright,
}:

buildPythonPackage (_finalAttrs: {
  pname = "playwright-captcha";
  version = "0.1.5";

  pyproject = true;

  src = fetchFromGitHub {
    owner = "techinz";
    repo = "playwright-captcha";
    rev = "2bdd880b6dd2c27133dc971f425f83e04c6c3849";
    hash = "sha256-XiJeh44CTUnTdEQgeAUiEmfjs4HZ8H+rG8Avll6K/tc=";
  };

  build-system = [
    setuptools
  ];

  dependencies = [
    twocaptcha_async
    playwright
  ];

  # Skip tests because they require network access.
  doCheck = false;

  # Author used their own fork, which has since been merged.
  dontCheckRuntimeDeps = true;

  pythonImportsCheck = [ "playwright_captcha" ];

  meta = {
    description = "Automating captcha solving for Playwright. Supports Cloudflare Turnstile & Interstitial, and reCAPTCHA V2 & V3 with Click-based or API (2captcha) solving. Designed for easy integration with Playwright, Patchright, and Camoufox. ";
    homepage = "https://github.com/techinz/playwright-captcha";
    license = lib.licenses.asl20;
  };
})
