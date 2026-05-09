{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
# Test key pairs (generated offline, for test use only — never use in production)
let
  serverPrivateKey = "OHuizKpqnG0fWUfIbQZpk3lm5VVDO3EbcJGJLbJcWHk=";
  serverPublicKey = "HbV4JZx1qOD+iOHQnuIbhl066vwliUYo39UA6/7ypBU=";
  clientPrivateKey = "mMkEkIbJRFXPIIvAaZqxqOIkS/jf1AAXU1yBPH2b9Wo=";
  clientPublicKey = "ok6MHFQbiCwnNFmZJ8RKfhNBegjCIWFreEuX+4NRySQ=";
in
pkgs.testers.runNixOSTest {
  name = "wireguard-integration-test";

  nodes = {
    # Minimal WireGuard server simulating a VPN provider peer
    server = _: {
      networking.enableIPv6 = false;

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

      networking.firewall.allowedUDPPorts = [
        51820
        53
      ];

      services.dnsmasq = {
        enable = true;
        settings = {
          interface = "wg0";
          bind-interfaces = true;
          listen-address = "10.100.0.1";
          log-queries = true;
          log-facility = "/var/log/dnsmasq-queries.log";
          address = [ "/test.vpn.local/10.100.0.1" ];
        };
      };
      systemd.services.dnsmasq = {
        after = [ "wireguard-wg0.service" ];
        wants = [ "wireguard-wg0.service" ];
      };
    };

    # nixflix client using the generic WireGuard provider
    client =
      { pkgs, ... }:
      {
        imports = [ nixosModules ];

        networking.enableIPv6 = false;

        # Without this, getaddrinfo("server") inside the wg namespace returns the
        # IPv6 address first (2001:db8:1::2), which wg setconf stores as the endpoint.
        # Since the namespace has no IPv6 route via the veth, the WireGuard handshake
        # never completes. Forcing IPv4 precedence fixes the endpoint resolution.
        environment.etc."gai.conf".text = "precedence ::ffff:0:0/96  100\n";

        virtualisation.cores = 4;

        environment.systemPackages = with pkgs; [
          dig
          tcpdump
        ];

        # vpn-confinement routes WireGuard's own UDP via veth/bridge (source 192.168.15.x).
        # Without MASQUERADE the server can't route back to 192.168.15.x, so the
        # WireGuard handshake never completes.
        networking.firewall.extraCommands = ''
          iptables -t nat -A POSTROUTING -s 192.168.15.0/24 -j MASQUERADE
        '';

        nixflix = {
          enable = true;

          vpn = {
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
                username = "admin";
                password._secret = pkgs.writeText "radarr-password" "testpass";
              };
              apiKey._secret = pkgs.writeText "radarr-apikey" "radarr11111111111111111111111111";
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

    # Service is stable (no crash loop) — give it a moment then check restart count
    import time
    time.sleep(5)

    radarr_restarts = client.succeed("systemctl show radarr.service -p NRestarts --value")
    assert radarr_restarts.strip() == "0", f"Radarr has restarted {radarr_restarts.strip()} times"

    # Verify Radarr is running inside the WG network namespace.
    # readlink /proc/<pid>/ns/net returns "net:[<namespace-id>]" — compare with the wg netns.
    radarr_pid = client.succeed("systemctl show radarr -p MainPID --value").strip()
    wg_ns = client.succeed("ip netns exec wg readlink /proc/self/ns/net").strip()
    radarr_ns = client.succeed(f"readlink /proc/{radarr_pid}/ns/net").strip()
    assert wg_ns == radarr_ns, f"Radarr (PID {radarr_pid}) is not in the wg namespace (expected {wg_ns}, got {radarr_ns})"

    # --- DNS leak tests ---
    server.wait_for_unit("dnsmasq.service")

    # resolv.conf inside the wg namespace contains only the VPN DNS server
    resolv = client.succeed("cat /etc/netns/wg/resolv.conf")
    assert "nameserver 10.100.0.1" in resolv, f"VPN DNS missing from resolv.conf: {resolv}"
    assert resolv.count("nameserver") == 1, f"Unexpected extra nameservers in resolv.conf: {resolv}"

    # iptables dns-fw chain allows only the VPN DNS server and DROPs everything else
    dns_rules = client.succeed("ip netns exec wg iptables -L dns-fw -n")
    assert "10.100.0.1" in dns_rules, f"VPN DNS server not in dns-fw chain: {dns_rules}"
    assert "DROP" in dns_rules, f"DROP rule missing from dns-fw chain: {dns_rules}"

    # Start tcpdump on the host-facing interface to capture any DNS packets that escape the namespace
    client.succeed("nohup tcpdump -i eth0 -n 'udp port 53' -w /tmp/dns-leak.pcap >/dev/null 2>&1 & echo $! > /tmp/tcpdump.pid")

    # DNS resolves correctly using the explicit VPN DNS server from inside the wg namespace
    # First ensure the WireGuard handshake has completed (tunnel is idle until first packet)
    client.wait_until_succeeds("ip netns exec wg ping -c1 -W2 10.100.0.1", timeout=30)
    server.succeed("echo > /var/log/dnsmasq-queries.log")
    dig_result = client.succeed("ip netns exec wg dig @10.100.0.1 test.vpn.local +short").strip()
    assert dig_result == "10.100.0.1", f"DNS resolved to unexpected address: {dig_result}"

    # DNS resolves using resolv.conf (no explicit server) — proves the namespace
    # picks up the VPN-provided nameserver rather than leaking to the host resolver
    dig_implicit = client.succeed("ip netns exec wg dig test.vpn.local +short").strip()
    assert dig_implicit == "10.100.0.1", f"Implicit DNS resolved to unexpected address: {dig_implicit}"

    # dnsmasq log confirms the queries were served through the VPN DNS server
    server.succeed("grep -q 'test.vpn.local' /var/log/dnsmasq-queries.log")

    # tcpdump shows zero DNS packets on the host-facing interface — no leak
    client.succeed("pkill tcpdump || true")
    leaked = client.succeed("tcpdump -r /tmp/dns-leak.pcap -nn 2>/dev/null | wc -l").strip()
    assert int(leaked) == 0, f"DNS leak detected: {leaked} packet(s) escaped the namespace on eth0"

    # VPN disruption: DNS fails when the WireGuard tunnel is blocked —
    # proves there is no fallback path that could leak queries
    server.succeed("iptables -I INPUT -p udp --dport 51820 -j DROP")
    server.succeed("iptables -I OUTPUT -p udp --sport 51820 -j DROP")
    client.fail("ip netns exec wg dig test.vpn.local +short +timeout=2 +tries=1")
    server.succeed("iptables -D INPUT -p udp --dport 51820 -j DROP")
    server.succeed("iptables -D OUTPUT -p udp --sport 51820 -j DROP")

    print("WireGuard integration test passed!")
  '';
}
