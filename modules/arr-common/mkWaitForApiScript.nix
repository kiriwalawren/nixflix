{
  lib,
  pkgs,
}: serviceName: serviceConfig:
pkgs.writeShellScript "${serviceName}-wait-for-api" (let
  mkSecureCurl = import ../lib/mk-secure-curl.nix {inherit lib pkgs;};
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in ''
  BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

  echo "Waiting for ${capitalizedName} API to be available..."
  for i in {1..90}; do
    if ${mkSecureCurl serviceConfig.apiKey {
    url = "$BASE_URL/system/status";
    extraArgs = "-f";
  }} >/dev/null 2>&1; then
      echo "${capitalizedName} API is available"
      exit 0
    fi
    echo "Waiting for ${capitalizedName} API... ($i/90)"
    sleep 1
  done

  echo "${capitalizedName} API not available after 90 seconds" >&2
  exit 1
'')
