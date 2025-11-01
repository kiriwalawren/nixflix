{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> {inherit system;},
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "mullvad-integration-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules];

    nixflix = {
      enable = true;
      mullvad = {
        enable = true;
        autoConnect = false; # Don't auto-connect in tests
        killSwitch = {
          enable = true;
          allowLan = true;
        };
        dns = ["1.1.1.1" "1.0.0.1"];
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for Mullvad daemon to start
    machine.wait_for_unit("mullvad-daemon.service", timeout=60)

    # Wait for Mullvad configuration service
    machine.wait_for_unit("mullvad-config.service", timeout=60)

    # Verify Mullvad daemon is running
    print("Checking Mullvad daemon status...")
    machine.succeed("mullvad status")

    # Verify lockdown mode (kill switch) is enabled
    print("Verifying kill switch is enabled...")
    status = machine.succeed("mullvad lockdown-mode get")
    assert "on" in status.lower(), f"Kill switch not enabled: {status}"

    # Verify LAN access is allowed
    print("Verifying LAN access is allowed...")
    lan_status = machine.succeed("mullvad lan get")
    assert "allow" in lan_status.lower(), f"LAN access not allowed: {lan_status}"

    # Verify DNS settings
    print("Verifying DNS settings...")
    dns_status = machine.succeed("mullvad dns get")
    assert "custom" in dns_status.lower(), f"Custom DNS not configured: {dns_status}"
    assert "1.1.1.1" in dns_status, f"DNS 1.1.1.1 not found in configuration: {dns_status}"
    assert "1.0.0.1" in dns_status, f"DNS 1.0.0.1 not found in configuration: {dns_status}"

    # Verify auto-connect is off (as configured)
    print("Verifying auto-connect is disabled...")
    autoconnect_status = machine.succeed("mullvad auto-connect get")
    assert "off" in autoconnect_status.lower(), f"Auto-connect not disabled: {autoconnect_status}"

    # Test that we can disconnect (service should handle this gracefully even when not connected)
    print("Testing disconnect command...")
    machine.succeed("mullvad disconnect || true")

    print("Mullvad integration test successful! Kill switch configured correctly.")
  '';
}
