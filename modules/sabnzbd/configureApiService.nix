{
  pkgs,
  lib,
  cfg,
}:
with lib; let
  configureScript =
    pkgs.writers.writePython3Bin "sabnzbd-configure-api" {
      libraries = with pkgs.python3Packages; [requests];
    } ''
      import requests
      import time
      import sys
      import os
      import json

      # Read API key from environment or file
      API_KEY = os.environ.get("SABNZBD_API_KEY", "")
      BASE_URL = os.environ.get("SABNZBD_BASE_URL", "")


      def api_call(mode, **params):
          """Make an API call to SABnzbd"""
          params.update({"mode": mode, "apikey": API_KEY, "output": "json"})
          try:
              response = requests.get(BASE_URL, params=params, timeout=10)
              response.raise_for_status()
              return response.json()
          except Exception as e:
              print(f"API call failed for mode={mode}: {e}", file=sys.stderr)
              return None


      def wait_for_sabnzbd():
          """Wait for SABnzbd to be ready"""
          print("Waiting for SABnzbd to be ready...")
          for i in range(60):
              try:
                  result = api_call("version")
                  if result and "version" in result:
                      print(f"SABnzbd is ready (version: {result['version']})")
                      return True
              except Exception:
                  pass
              time.sleep(1)
          print("SABnzbd did not become ready in time", file=sys.stderr)
          return False


      def set_config(section, keyword, value):
          """Set a configuration value"""
          result = api_call("set_config", section=section, keyword=keyword,
                            value=value)
          if result:
              print(f"Set {section}.{keyword} = {value}")
              return True
          return False


      def configure_misc_settings():
          """Configure misc settings via API"""
          print("Configuring misc settings...")
          settings_json = os.environ.get("SETTINGS_JSON", "{}")
          settings = json.loads(settings_json)

          for key, value in settings.items():
              # Convert booleans to 0/1
              if isinstance(value, bool):
                  value = 1 if value else 0
              set_config("misc", key, str(value))


      def configure_servers():
          """Configure SABnzbd servers via API"""
          print("Configuring servers...")
          servers_json = os.environ.get("SERVERS_JSON", "[]")
          servers = json.loads(servers_json)

          for server in servers:
              name = server["name"]
              # Read secrets from environment if they're placeholders
              username = server["username"]
              password = server["password"]

              if username.startswith("$"):
                  username = os.environ.get(username[1:], username)
              if password.startswith("$"):
                  password = os.environ.get(password[1:], password)

              params = {
                  "section": "servers",
                  "name": name,
                  "host": server["host"],
                  "port": server["port"],
                  "username": username,
                  "password": password,
                  "connections": server["connections"],
                  "ssl": 1 if server["ssl"] else 0,
                  "priority": server["priority"],
                  "optional": 1 if server["optional"] else 0,
                  "retention": server["retention"],
                  "enable": 1 if server["enable"] else 0,
              }

              result = api_call("set_config", **params)
              if result:
                  print(f"Configured server: {name}")


      def configure_categories():
          """Configure SABnzbd categories via API"""
          print("Configuring categories...")
          categories_json = os.environ.get("CATEGORIES_JSON", "[]")
          categories = json.loads(categories_json)

          for category in categories:
              name = category["name"]
              params = {
                  "section": "categories",
                  "name": name,
                  "dir": category["dir"],
                  "priority": category["priority"],
                  "pp": category["pp"],
                  "script": category["script"],
              }

              result = api_call("set_config", **params)
              if result:
                  print(f"Configured category: {name}")


      if __name__ == "__main__":
          if not wait_for_sabnzbd():
              sys.exit(1)

          configure_misc_settings()
          configure_servers()
          configure_categories()

          print("SABnzbd configuration completed successfully")
    '';
in {
  script = configureScript;

  serviceConfig = {
    description = "Configure SABnzbd via API";
    after = ["sabnzbd.service"];
    bindsTo = ["sabnzbd.service"];
    wantedBy = ["sabnzbd.service"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Export API key
      ${optionalString (cfg.apiKeyPath != null) ''
        export SABNZBD_API_KEY=$(${pkgs.coreutils}/bin/cat ${cfg.apiKeyPath})
      ''}

      # Export base URL
      export SABNZBD_BASE_URL="http://${cfg.settings.host}:${toString cfg.settings.port}${cfg.settings.url_base}/api"

      # Export configuration as JSON
      export SETTINGS_JSON='${builtins.toJSON (filterAttrs (n: v: n != "servers" && n != "categories") cfg.settings)}'
      export SERVERS_JSON='${builtins.toJSON cfg.settings.servers}'
      export CATEGORIES_JSON='${builtins.toJSON cfg.settings.categories}'

      # Export environment secrets
      ${concatMapStringsSep "\n" (secret: ''
          export ${secret.env}=$(${pkgs.coreutils}/bin/cat ${secret.path})
        '')
        cfg.environmentSecrets}

      # Run configuration script
      ${configureScript}/bin/sabnzbd-configure-api
    '';
  };
}
