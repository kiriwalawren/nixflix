{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "navidrome-users";

  nodes.machine = {
    imports = [ nixosModules ];

    virtualisation = {
      diskSize = 2 * 1024;
      memorySize = 2048;
    };

    nixflix = {
      enable = true;

      navidrome = {
        enable = true;

        users = {
          kiri = {
            isAdmin = true;
            mutable = false;
            password._secret = pkgs.writeText "kiri_password" "321password";
            email = "kiri@example.com";
          };

          bob = {
            isAdmin = false;
            mutable = false;
            password = "password123";
            email = "bob@example.com";
          };
        };
      };
    };
  };

  testScript = ''
    start_all()

    import json

    port = 4533
    machine.wait_for_unit("navidrome.service", timeout=180)
    machine.wait_for_open_port(port, timeout=180)

    machine.wait_for_unit("navidrome-create-admin.service", timeout=180)
    machine.wait_for_unit("navidrome-users-config.service", timeout=180)

    base_url = f"http://127.0.0.1:{port}"

    print("Logging in as kiri...")
    login_payload = json.dumps({"username": "kiri", "password": "321password"})
    login_response = machine.succeed(
        f"curl -sf -X POST -H 'Content-Type: application/json' "
        f"-d '{login_payload}' {base_url}/auth/login"
    )
    token = json.loads(login_response)["token"]

    users_json = machine.succeed(
        f"curl -sf -H 'x-nd-authorization: Bearer {token}' "
        f"'{base_url}/api/user?_end=200&_order=ASC&_sort=userName&_start=0'"
    )

    users = json.loads(users_json)
    assert len(users) == 2, f"Expected 2 users, found {len(users)}"

    kiri_users = [u for u in users if u["userName"] == "kiri"]
    assert len(kiri_users) == 1, f"Expected 1 user named kiri, found {len(kiri_users)}"
    kiri = kiri_users[0]
    assert kiri["isAdmin"] == True, f"kiri should be admin, got {kiri['isAdmin']}"
    assert kiri["email"] == "kiri@example.com", f"kiri email mismatch, got {kiri['email']}"

    bob_users = [u for u in users if u["userName"] == "bob"]
    assert len(bob_users) == 1, f"Expected 1 user named bob, found {len(bob_users)}"
    bob = bob_users[0]
    assert bob["isAdmin"] == False, f"bob should not be admin, got {bob['isAdmin']}"
    assert bob["email"] == "bob@example.com", f"bob email mismatch, got {bob['email']}"

    print("All Navidrome user assertions passed!")
  '';
}
