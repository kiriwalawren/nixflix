{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  testUsername = "admin";
  testPassword = "TestPassword!@#$%^&*";
in
pkgs.testers.runNixOSTest {
  name = "aurral-basic-test";

  nodes.machine = {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 3072;
      diskSize = 3 * 1024;
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

      aurral = {
        enable = true;

        settings.users.admin = {
          username = testUsername;
          role = "admin";
          password._secret = pkgs.writeText "aurral-admin-password" testPassword;
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

    print("All Aurral login assertions passed!")
  '';
}
