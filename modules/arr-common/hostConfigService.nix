{
  lib,
  pkgs,
  restishPackage,
}:
# Helper function to create a systemd service that configures *arr basic settings via API
serviceName: serviceConfig:
with lib; let
  mkWaitForApiScript = import ./mkWaitForApiScript.nix {
    inherit lib pkgs restishPackage;
  };
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  description = "Configure ${serviceName} via API";
  after = ["${serviceName}.service"];
  wantedBy = ["multi-user.target"];

  path = [restishPackage pkgs.jq];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStartPre = mkWaitForApiScript serviceName serviceConfig;
  };

  script = ''
    set -eu

    # Read password secret
    AUTH_PASSWORD=$(cat ${serviceConfig.hostConfig.passwordPath})

    # Get current host configuration
    echo "Fetching current host configuration..."
    HOST_CONFIG=$(restish -o json ${serviceName}/config/host)

    if [ -z "$HOST_CONFIG" ]; then
      echo "Failed to fetch host configuration"
      exit 1
    fi

    # Extract the ID from the host config (needed for PUT request)
    CONFIG_ID=$(echo "$HOST_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

    # Read API key for config JSON
    API_KEY=$(cat ${serviceConfig.apiKeyPath})

    # Build the complete configuration JSON
    echo "Building configuration..."
    NEW_CONFIG=$(${pkgs.jq}/bin/jq -n \
      --arg apiKey "$API_KEY" \
      --arg password "$AUTH_PASSWORD" \
      --argjson id "$CONFIG_ID" \
      '{
        id: $id,
        bindAddress: "${serviceConfig.hostConfig.bindAddress}",
        port: ${builtins.toString serviceConfig.hostConfig.port},
        sslPort: ${builtins.toString serviceConfig.hostConfig.sslPort},
        enableSsl: ${boolToString serviceConfig.hostConfig.enableSsl},
        launchBrowser: ${boolToString serviceConfig.hostConfig.launchBrowser},
        authenticationMethod: "${serviceConfig.hostConfig.authenticationMethod}",
        authenticationRequired: "${serviceConfig.hostConfig.authenticationRequired}",
        analyticsEnabled: ${boolToString serviceConfig.hostConfig.analyticsEnabled},
        username: "${serviceConfig.hostConfig.username}",
        password: $password,
        passwordConfirmation: $password,
        logLevel: "${serviceConfig.hostConfig.logLevel}",
        logSizeLimit: ${builtins.toString serviceConfig.hostConfig.logSizeLimit},
        consoleLogLevel: "${serviceConfig.hostConfig.consoleLogLevel}",
        branch: "${serviceConfig.hostConfig.branch}",
        apiKey: $apiKey,
        sslCertPath: "${serviceConfig.hostConfig.sslCertPath}",
        sslCertPassword: "${serviceConfig.hostConfig.sslCertPassword}",
        urlBase: "${serviceConfig.hostConfig.urlBase}",
        instanceName: "${serviceConfig.hostConfig.instanceName}",
        applicationUrl: "${serviceConfig.hostConfig.applicationUrl}",
        updateAutomatically: ${boolToString serviceConfig.hostConfig.updateAutomatically},
        updateMechanism: "${serviceConfig.hostConfig.updateMechanism}",
        updateScriptPath: "${serviceConfig.hostConfig.updateScriptPath}",
        proxyEnabled: ${boolToString serviceConfig.hostConfig.proxyEnabled},
        proxyType: "${serviceConfig.hostConfig.proxyType}",
        proxyHostname: "${serviceConfig.hostConfig.proxyHostname}",
        proxyPort: ${builtins.toString serviceConfig.hostConfig.proxyPort},
        proxyUsername: "${serviceConfig.hostConfig.proxyUsername}",
        proxyPassword: "${serviceConfig.hostConfig.proxyPassword}",
        proxyBypassFilter: "${serviceConfig.hostConfig.proxyBypassFilter}",
        proxyBypassLocalAddresses: ${boolToString serviceConfig.hostConfig.proxyBypassLocalAddresses},
        certificateValidation: "${serviceConfig.hostConfig.certificateValidation}",
        backupFolder: "${serviceConfig.hostConfig.backupFolder}",
        backupInterval: ${builtins.toString serviceConfig.hostConfig.backupInterval},
        backupRetention: ${builtins.toString serviceConfig.hostConfig.backupRetention},
        trustCgnatIpAddresses: ${boolToString serviceConfig.hostConfig.trustCgnatIpAddresses}
      }')

    # Update host configuration
    echo "Updating ${capitalizedName} configuration via API..."
    echo "$NEW_CONFIG" | restish put ${serviceName}/config/host/$CONFIG_ID > /dev/null

    echo "Configuration updated successfully"

    # Restart the service to pick up the new configuration
    echo "Restarting ${serviceName} service..."
    systemctl restart ${serviceName}.service
    echo "${capitalizedName} service restarted"
  '';
}
