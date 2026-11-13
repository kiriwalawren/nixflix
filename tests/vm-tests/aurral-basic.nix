{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  testUsername = "admin";
  testPassword = "TestPassword!@#$%^&*";
  testApiKey = "abcd1234abcd1234abcd1234abcd1234";
  jellyfinApiKey = "jellyfinApiKey1111111111111111111";
  navidromePassword = "navidromepassword";
  listenerPassword = "listenerpassword";
in
pkgs.testers.runNixOSTest {
  name = "aurral-basic-test";

  nodes.machine = {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 4 * 1024;
    };

    nixflix = {
      enable = true;

      lidarr = {
        enable = true;
        mediaDirs = [ "/media/music" ];
        config = {
          hostConfig = {
            username = "admin";
            password._secret = pkgs.writeText "lidarr-password" "testpassword123";
          };
          apiKey._secret = pkgs.writeText "lidarr-apikey" "5678efgh5678efgh5678efgh5678efgh";
        };
      };

      jellyfin = {
        enable = true;
        apiKey._secret = pkgs.writeText "jellyfin-apikey" jellyfinApiKey;
        users.jfadmin = {
          password._secret = pkgs.writeText "jellyfin-admin-password" "jellyfinpassword";
          policy.isAdministrator = true;
        };
      };

      navidrome = {
        enable = true;
        users.ndadmin = {
          userName = "ndadmin";
          isAdmin = true;
          password._secret = pkgs.writeText "navidrome-admin-password" navidromePassword;
        };
      };

      aurral = {
        enable = true;
        apiKey._secret = pkgs.writeText "aurral-apikey" testApiKey;

        settings.users = {
          admin = {
            username = testUsername;
            role = "admin";
            password._secret = pkgs.writeText "aurral-admin-password" testPassword;
          };

          listener = {
            mutable = false;
            password._secret = pkgs.writeText "aurral-listener-password" listenerPassword;
            permissions.accessFlow = true;
          };
        };
      };
    };
  };

  testScript = ''
    import json

    start_all()

    port = 5030
    machine.wait_for_unit("lidarr.service", timeout=180)
    machine.wait_for_unit("lidarr-config.service", timeout=180)
    machine.wait_for_unit("aurral.service", timeout=180)
    machine.wait_for_open_port(port, timeout=180)
    machine.wait_for_unit("aurral-setup.service", timeout=180)
    machine.wait_for_unit("aurral-lidarr.service", timeout=180)
    machine.wait_for_unit("aurral-jellyfin.service", timeout=300)
    machine.wait_for_unit("aurral-navidrome.service", timeout=180)
    machine.wait_for_unit("aurral-users-config.service", timeout=180)

    base_url = f"http://127.0.0.1:{port}"

    print("Checking onboarding is no longer required...")
    bootstrap_json = machine.succeed(f"curl -sf {base_url}/api/health/bootstrap")
    bootstrap = json.loads(bootstrap_json)
    assert bootstrap.get("onboardingRequired") == False, \
        f"Expected onboarding to be complete, got {bootstrap}"

    print("Logging in with the special-character admin password...")
    login_payload = json.dumps({"username": "${testUsername}", "password": "${testPassword}"})
    login_response = machine.succeed(
        f"curl -sf -X POST -H 'Content-Type: application/json' "
        f"-d '{login_payload}' {base_url}/api/auth/login"
    )
    print(f"Login response: {login_response}")

    print("Checking the declarative API key authenticates and is env-managed...")
    api_key_json = machine.succeed(
        f"curl -sf -H 'X-Api-Key: ${testApiKey}' {base_url}/api/auth/api-key"
    )
    api_key = json.loads(api_key_json)
    assert api_key == {"apiKey": "${testApiKey}", "managedByEnv": True}, \
        f"Expected AURRAL_API_KEY to be in use, got {api_key}"

    print("Checking aurral-lidarr configured Lidarr through the settings API...")
    settings = json.loads(machine.succeed(
        f"curl -sf -H 'X-Api-Key: ${testApiKey}' {base_url}/api/settings"
    ))
    lidarr = settings["integrations"]["lidarr"]
    assert lidarr.get("enabled") is not False, f"Expected Lidarr enabled, got {lidarr}"
    assert lidarr.get("qualityProfileId"), f"Expected a quality profile ID, got {lidarr}"
    assert lidarr.get("metadataProfileId"), f"Expected a metadata profile ID, got {lidarr}"

    print("Checking the Jellyfin integration resolved the admin user and uses the nixflix API key...")
    jellyfin = settings["integrations"]["jellyfin"]
    jellyfin_users = json.loads(machine.succeed(
        "curl -sf -H 'Authorization: MediaBrowser Token=\"${jellyfinApiKey}\"' http://127.0.0.1:8096/Users"
    ))
    jfadmin_id = next(u["Id"] for u in jellyfin_users if u["Name"] == "jfadmin")
    assert jellyfin == {"url": "http://127.0.0.1:8096", "apiKey": "${jellyfinApiKey}", "userId": jfadmin_id}, \
        f"Unexpected Jellyfin integration: {jellyfin}"

    print("Checking the Navidrome integration and that Aurral can log in with it...")
    navidrome = settings["integrations"]["navidrome"]
    assert navidrome.get("url") == "http://127.0.0.1:4533", f"Unexpected Navidrome url: {navidrome}"
    assert navidrome.get("username") == "ndadmin", f"Unexpected Navidrome username: {navidrome}"
    assert navidrome.get("password") == "${navidromePassword}", "Navidrome password was not saved"
    test_payload = json.dumps({k: navidrome[k] for k in ("url", "username", "password")})
    machine.succeed(
        f"curl -sf -X POST -H 'X-Api-Key: ${testApiKey}' -H 'Content-Type: application/json' "
        f"-d '{test_payload}' {base_url}/api/settings/navidrome/test"
    )

    print("Checking Aurral and nixflix agree on the Navidrome library name across an Aurral restart...")
    nd_token = json.loads(machine.succeed(
        "curl -sf -X POST -H 'Content-Type: application/json' "
        "-d '{\"username\": \"ndadmin\", \"password\": \"${navidromePassword}\"}' "
        "http://127.0.0.1:4533/auth/login"
    ))["token"]

    def aurral_library_names():
        libraries = json.loads(machine.succeed(
            f"curl -sf -H 'X-ND-Authorization: Bearer {nd_token}' "
            "'http://127.0.0.1:4533/api/library?_start=0&_end=1000'"
        ))
        return [l["name"] for l in libraries if l["path"] == "/data/media/aurral"]

    assert aurral_library_names() == ["Aurral Playlists"], aurral_library_names()
    machine.succeed("systemctl restart aurral.service")
    machine.wait_for_open_port(port, timeout=180)
    machine.succeed("systemctl restart navidrome-libraries.service")
    assert aurral_library_names() == ["Aurral Playlists"], aurral_library_names()
    machine.fail("journalctl -u navidrome-libraries.service | grep -q 'Updated library'")

    print("Checking aurral-users-config created the declared listener user...")
    def get_listener():
        users = json.loads(machine.succeed(
            f"curl -sf -H 'X-Api-Key: ${testApiKey}' {base_url}/api/users"
        ))
        return next(u for u in users if u["username"] == "listener")

    listener = get_listener()
    assert listener["role"] == "user", f"Unexpected listener role: {listener}"
    assert listener["permissions"]["accessFlow"] is True, f"Unexpected listener permissions: {listener}"

    listener_login = json.dumps({"username": "listener", "password": "${listenerPassword}"})
    machine.succeed(
        f"curl -sf -X POST -H 'Content-Type: application/json' "
        f"-d '{listener_login}' {base_url}/api/auth/login"
    )

    print("Checking mutable = false restores the listener's role and permissions...")
    drift = json.dumps({"role": "admin", "permissions": {"accessFlow": False}})
    machine.succeed(
        f"curl -sf -X PATCH -H 'X-Api-Key: ${testApiKey}' -H 'Content-Type: application/json' "
        f"-d '{drift}' {base_url}/api/users/{listener['id']}"
    )
    assert get_listener()["role"] == "admin", "PATCH did not change the listener"
    machine.succeed("systemctl restart aurral-users-config.service")
    listener = get_listener()
    assert listener["role"] == "user", f"Listener role was not restored: {listener}"
    assert listener["permissions"]["accessFlow"] is True, f"Listener permissions were not restored: {listener}"

    print("All Aurral login assertions passed!")
  '';
}
