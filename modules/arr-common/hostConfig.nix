{
  lib,
  pkgs,
  serviceName,
}:
with lib; let
  secrets = import ../lib/secrets {inherit lib;};
  mkSecureCurl = import ../lib/mk-secure-curl.nix {inherit lib pkgs;};
  mkWaitForApiScript = import ./mkWaitForApiScript.nix {inherit lib pkgs;};
  capitalizedName = lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
in {
  options = mkOption {
    type = import ./hostConfigType.nix {inherit lib;};
    default = {};
    description = "Host configuration options that will be set via the API /config/host endpoint";
  };

  mkService = serviceConfig: let
    jqSecrets = secrets.mkJqSecretArgs {
      inherit (serviceConfig) apiKey;
      inherit (serviceConfig.hostConfig) password;
    };
  in {
    description = "Configure ${serviceName} via API";
    after = ["${serviceName}.service"];
    # DO NOT ADD `requires` here <service>-config restarts
    # the service and enter failed state as a result
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = mkWaitForApiScript serviceName serviceConfig;
      ExecStartPost = mkWaitForApiScript serviceName serviceConfig;
    };

    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      # Get current host configuration
      echo "Fetching current host configuration..."
      HOST_CONFIG=$(${mkSecureCurl serviceConfig.apiKey {
        url = "$BASE_URL/config/host";
        extraArgs = "-f";
      }} 2>/dev/null)

      if [ -z "$HOST_CONFIG" ]; then
        echo "Failed to fetch host configuration"
        exit 1
      fi

      # Extract the ID from the host config (needed for PUT request)
      CONFIG_ID=$(echo "$HOST_CONFIG" | ${pkgs.jq}/bin/jq -r '.id')

      # Build the complete configuration JSON
      echo "Building configuration..."
      NEW_CONFIG=$(${pkgs.jq}/bin/jq -n \
        ${jqSecrets.flagsString} \
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
          password: ${jqSecrets.refs.password},
          passwordConfirmation: ${jqSecrets.refs.password},
          logLevel: "${serviceConfig.hostConfig.logLevel}",
          logSizeLimit: ${builtins.toString serviceConfig.hostConfig.logSizeLimit},
          consoleLogLevel: "${serviceConfig.hostConfig.consoleLogLevel}",
          branch: "${serviceConfig.hostConfig.branch}",
          apiKey: ${jqSecrets.refs.apiKey},
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
      ${mkSecureCurl serviceConfig.apiKey {
        url = "$BASE_URL/config/host/$CONFIG_ID";
        method = "PUT";
        headers = {"Content-Type" = "application/json";};
        data = "$NEW_CONFIG";
        extraArgs = "-f";
      }} > /dev/null

      echo "Configuration updated successfully"

      # Restart the service to pick up the new configuration
      echo "Restarting ${serviceName} service..."
      systemctl restart ${serviceName}.service
      echo "${capitalizedName} service restarted"
    '';
  };
}
