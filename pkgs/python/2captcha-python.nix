{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  requests,
  httpx,
  aiofiles,

}:

buildPythonPackage (finalAttrs: {
  pname = "2captcha-python";
  version = "2.0.9";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "2captcha";
    repo = "2captcha-python";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bfeWuCvtVIl5JED6nDVYOpmVNRAwPt2fj9gudLIWAOU=";
  };

  build-system = [
    setuptools
  ];

  dependencies = [
    requests
    httpx
    aiofiles
  ];

  # Skip tests because they require network access.
  doCheck = false;

  pythonImportsCheck = [ "twocaptcha" ];

  meta = {
    description = "Python 3 package for easy integration with the API of 2captcha captcha solving service to bypass recaptcha, сloudflare turnstile, funcaptcha, geetest and solve any other captchas. ";
    mainProgram = "2captcha";
    homepage = "https://github.com/2captcha/2captcha-python";
    license = lib.licenses.mit;
  };
})
