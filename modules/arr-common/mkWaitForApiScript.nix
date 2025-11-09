{
  lib,
  pkgs,
}: serviceName: serviceConfig:
pkgs.writeShellScript "${serviceName}-wait-for-api" (let
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
  screamingName = lib.toUpper serviceName;
  apiKeyEnvVar = screamingName + "__AUTH__APIKEY";
in ''
  if [ -n "${"$"}{${apiKeyEnvVar}:-}" ]; then
    API_KEY="${"$"}${apiKeyEnvVar}"
  else
    API_KEY=$(cat ${serviceConfig.apiKeyPath})
  fi

  BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

  echo "Waiting for ${capitalizedName} API to be available..."
  for i in {1..90}; do
    if ${pkgs.curl}/bin/curl -s -f "$BASE_URL/system/status?apiKey=$API_KEY" >/dev/null 2>&1; then
      echo "${capitalizedName} API is available"
      exit 0
    fi
    echo "Waiting for ${capitalizedName} API... ($i/90)"
    sleep 1
  done

  echo "${capitalizedName} API not available after 90 seconds" >&2
  exit 1
'')
