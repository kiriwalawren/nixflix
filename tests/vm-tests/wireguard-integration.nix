{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
# Test key pairs (generated offline, for test use only — never use in production)
let
  serverPrivateKey = "OHuizKpqnG0fWUfIbQZpk3lm5VVDO3EbcJGJLbJcWHk=";
  serverPublicKey = "eCq2XFOVF58+VmKIkUmpQ4hf7BFQB5r5e7M4E0XAXEE=";
  clientPrivateKey = "mMkEkIbJRFXPIIvAaZqxqOIkS/jf1AAXU1yBPH2b9Wo=";
  clientPublicKey = "LMlEUhWdh5MFrIBiK8ulyH0tqJTU0NxbVzYU5vBEBAY=";
in
pkgs.testers.runNixOSTest {
  name = "wireguard-integration-test";

  nodes = {
    # Minimal WireGuard server simulating a VPN provider peer
    server = _: {
      networking.wireguard.interfaces.wg0 = {
        ips = [ "10.100.0.1/24" ];
        listenPort = 51820;
        privateKey = serverPrivateKey;
        peers = [
          {
            publicKey = clientPublicKey;
            allowedIPs = [ "10.100.0.2/32" ];
          }
        ];
      };

      networking.firewall.allowedUDPPorts = [ 51820 ];
    };

    # nixflix client using the generic WireGuard provider
    client =
      { pkgs, ... }:
      {
        imports = [ nixosModules ];

        virtualisation.cores = 4;

        nixflix = {
          enable = true;

          vpn.wireguard = {
            enable = true;
            wgConfFile = pkgs.writeText "wg0.conf" ''
              [Interface]
              Address = 10.100.0.2/24
              PrivateKey = ${clientPrivateKey}
              DNS = 10.100.0.1

              [Peer]
              PublicKey = ${serverPublicKey}
              Endpoint = server:51820
              AllowedIPs = 0.0.0.0/0
            '';
            accessibleFrom = [ "192.168.1.0/24" ];
          };

          radarr = {
            enable = true;
            vpn.enable = true; # confined to WG netns
            config = {
              hostConfig = {
                port = 7878;
                username = "admin";
                password._secret = pkgs.writeText "radarr-password" "testpass";
              };
              apiKey._secret = pkgs.writeText "radarr-apikey" "radarr333333333333333333333333333";
            };
          };

          prowlarr = {
            enable = true;
            vpn.enable = false; # bypasses VPN (runs outside netns)
            config = {
              hostConfig = {
                port = 9696;
                username = "admin";
                password._secret = pkgs.writeText "prowlarr-password" "testpass";
              };
              apiKey._secret = pkgs.writeText "prowlarr-apikey" "prowlarr11111111111111111111111111";
            };
          };
        };
      };
  };

  testScript = ''
    start_all()

    server.wait_for_unit("wireguard-wg0.service")

    # Wait for VPN-Confinement namespace to be up
    client.wait_for_unit("wg.service", timeout=60)

    # WireGuard network namespace was created
    client.succeed("ip netns list | grep -q wg")

    # Confined service (Radarr) starts and its port is reachable via the VPN-Confinement bridge
    # (namespaceAddress = 192.168.15.1; port mapped from host to wg netns)
    client.wait_for_unit("radarr.service", timeout=120)
    client.wait_for_open_port(7878, addr="192.168.15.1", timeout=60)

    # Bypass service (Prowlarr) starts and its port is reachable on localhost
    client.wait_for_unit("prowlarr.service", timeout=120)
    client.wait_for_open_port(9696, timeout=60)

    # Services are stable (no crash loops)
    import time
    time.sleep(5)
    client.succeed("systemctl is-active radarr.service")
    client.succeed("systemctl is-active prowlarr.service")

    radarr_restarts = client.succeed("systemctl show radarr.service -p NRestarts --value")
    assert radarr_restarts.strip() == "0", f"Radarr has restarted {radarr_restarts.strip()} times"

    prowlarr_restarts = client.succeed("systemctl show prowlarr.service -p NRestarts --value")
    assert prowlarr_restarts.strip() == "0", f"Prowlarr has restarted {prowlarr_restarts.strip()} times"

    # Verify Radarr is running inside the WG network namespace.
    # readlink /proc/<pid>/ns/net returns "net:[<namespace-id>]" — compare with the wg netns.
    radarr_pid = client.succeed("systemctl show radarr -p MainPID --value").strip()
    wg_ns = client.succeed("ip netns exec wg readlink /proc/self/ns/net").strip()
    radarr_ns = client.succeed(f"readlink /proc/{radarr_pid}/ns/net").strip()
    assert wg_ns == radarr_ns, f"Radarr (PID {radarr_pid}) is not in the wg namespace (expected {wg_ns}, got {radarr_ns})"

    # Verify Prowlarr is NOT in the WG namespace (running in the host netns)
    prowlarr_pid = client.succeed("systemctl show prowlarr -p MainPID --value").strip()
    prowlarr_ns = client.succeed(f"readlink /proc/{prowlarr_pid}/ns/net").strip()
    assert wg_ns != prowlarr_ns, f"Prowlarr (PID {prowlarr_pid}) is unexpectedly confined to the wg namespace"

    # Bypass service can reach the host network
    client.succeed("ping -c1 -W5 server")

    print("WireGuard integration test passed!")
  '';
}
