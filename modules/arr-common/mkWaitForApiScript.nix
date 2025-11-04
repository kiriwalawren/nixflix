{
  lib,
  pkgs,
  restishPackage,
}:
# Helper function to create a script that waits for an *arr service API to be ready
serviceName: serviceConfig:
pkgs.writeShellScript "${serviceName}-wait-for-api" (let
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in ''
  export PATH="${restishPackage}/bin:$PATH"

  echo "Waiting for ${capitalizedName} API to be available..."
  for i in {1..90}; do
    if restish -o json ${serviceName}/system/status >/dev/null; then
      echo "${capitalizedName} API is available"
      exit 0
    fi
    echo "Waiting for ${capitalizedName} API... ($i/90)"
    sleep 1
  done

  echo "${capitalizedName} API not available after 90 seconds" >&2
  exit 1
'')
