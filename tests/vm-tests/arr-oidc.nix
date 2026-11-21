{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  pkgsUnfree = import pkgs.path {
    inherit system;
    config.allowUnfree = true;
  };
  # Test-only certificate/key and credentials; never use these in a real deployment.
  testTls =
    pkgsUnfree.runCommand "arr-oidc-test-tls" { nativeBuildInputs = [ pkgsUnfree.openssl ]; }
      ''
        mkdir -p "$out"
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
          -subj /CN=radarr.test -addext 'subjectAltName=DNS:radarr.test,DNS:dex.test' \
          -keyout "$out/key.pem" -out "$out/cert.pem"
      '';
  python = pkgsUnfree.python3.withPackages (ps: [
    ps.requests
    ps.beautifulsoup4
  ]);
in
pkgsUnfree.testers.runNixOSTest {
  name = "arr-oidc-test";

  nodes.machine = { pkgs, ... }: {
    imports = [ nixosModules ];

    virtualisation = {
      cores = 4;
      memorySize = 4096;
    };
    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
    security.pki.certificateFiles = [ "${testTls}/cert.pem" ];
    networking.hosts."127.0.0.1" = [ "dex.test" ];

    services.dex = {
      enable = true;
      settings = {
        issuer = "https://dex.test/dex";
        storage = {
          type = "sqlite3";
          config.file = "/run/dex/dex.db";
        };
        web.http = "127.0.0.1:5556";
        oauth2.skipApprovalScreen = true;
        staticClients = [
          {
            id = "radarr";
            name = "Radarr test client";
            secret = "test-only-oidc-client-secret";
            redirectURIs = [ "https://radarr.test/signin-oidc" ];
          }
        ];
        connectors = [
          {
            type = "mockPassword";
            id = "mock";
            name = "Test login";
            config = {
              username = "testuser";
              password = "testpassword";
            };
          }
        ];
      };
    };

    nixflix = {
      enable = true;
      caddy = {
        enable = true;
        domain = "test";
        addHostsEntries = true;
        tls = {
          enable = true;
          certFile = "${testTls}/cert.pem";
          keyFile = "${testTls}/key.pem";
        };
      };
      radarr = {
        enable = true;
        mediaDirs = [ "/media/movies" ];
        config = {
          apiKey._secret = pkgs.writeText "radarr-test-api-key" "0123456789abcdef0123456789abcdef";
          hostConfig = {
            port = 7878;
            applicationUrl = "https://radarr.test";
            authenticationMethod = "oidc";
            username = null;
            trustedNetworks = "127.0.0.1";
            oidc = {
              authority = "https://dex.test/dex";
              clientId = "radarr";
              clientSecret._secret = pkgs.writeText "radarr-test-oidc-secret" "test-only-oidc-client-secret";
              userIdentifier = "kilgore@kilgore.trout"; # Dex mockPassword's fixed test identity
            };
          };
        };
      };
    };

    # Radarr validates OIDC discovery while applying its host configuration.
    systemd.services.radarr-config.after = [
      "dex.service"
      "caddy.service"
    ];
    systemd.services.radarr-config.wants = [
      "dex.service"
      "caddy.service"
    ];

    services.caddy.virtualHosts."dex.test".extraConfig = ''
      tls ${testTls}/cert.pem ${testTls}/key.pem
      reverse_proxy 127.0.0.1:5556
    '';
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("dex.service", timeout=120)
    machine.wait_for_unit("caddy.service", timeout=120)
    machine.wait_for_unit("radarr-config.service", timeout=240)
    machine.wait_for_open_port(7878, timeout=120)
    machine.wait_until_succeeds("curl -fsS https://dex.test/dex/.well-known/openid-configuration", timeout=120)
    machine.succeed(
        "curl -fsS -H 'X-Api-Key: 0123456789abcdef0123456789abcdef' "
        "http://127.0.0.1:7878/api/v3/config/host | "
        "jq -e '.authenticationMethod == \"oidc\" and .oidcClientId == \"radarr\"'"
    )
    machine.succeed("${python}/bin/python ${../lib/oidc-login.py}")
  '';
}
