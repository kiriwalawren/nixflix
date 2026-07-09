{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  setuptools,

  # dependencies
  requests,
  httpx,
  aiofiles,

}:

buildPythonPackage (finalAttrs: {
  pname = "2captcha-python-async";
  version = "1.5.1";
  pyproject = true;

  src = fetchPypi {
    inherit (finalAttrs) version;
    pname = "2captcha_python_async";
    hash = "sha256-ydW3PdrCOovNwblrB19xZZRcDXmDb4Nw04AtnFirMjY=";
  };

  build-system = [
    setuptools
  ];

  dependencies = [
    requests
    httpx
    aiofiles
  ];

  pythonImportsCheck = [ "twocaptcha" ];

  meta = {
    description = "Python 3 package for easy integration with the API of 2captcha captcha solving service to bypass recaptcha, сloudflare turnstile, funcaptcha, geetest and solve any other captchas. ";
    mainProgram = "2captcha";
    homepage = "https://github.com/2captcha/2captcha-python";
    license = lib.licenses.mit;
  };
})
