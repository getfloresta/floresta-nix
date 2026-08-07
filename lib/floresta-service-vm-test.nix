# SPDX-License-Identifier: MIT OR Apache-2.0

# NixOS VM integration test for floresta-service.nix
# Boots a VM, starts the floresta service, and verifies systemd integration.
# Linux only.
{ pkgs, flakeInputs }:

let
  # Dummy florestad that listens briefly so systemd considers it started
  dummyPkg = pkgs.writeShellScriptBin "florestad" ''
    echo "floresta-dummy: $@"
    # Stay alive so systemd doesn't restart immediately
    sleep infinity
  '';

  test = pkgs.nixosTest {
    name = "floresta-service-vm-test";

    nodes.machine =
      { ... }:
      {
        imports = [ flakeInputs.self.nixosModules.floresta ];

        services.floresta = {
          enable = true;
          package = dummyPkg;
          network = "signet";
          debug = true;
          rpc.address = "127.0.0.1:38332";
          electrum.address = "127.0.0.1:50001";
        };
      };

    testScript = ''
      machine.wait_for_unit("floresta.service")

      # Verify the service is running
      machine.succeed("systemctl is-active floresta.service")

      # Verify user and group were created
      machine.succeed("id floresta")
      machine.succeed("getent group floresta")

      # Verify data directory exists and is owned by floresta
      machine.succeed("test -d /var/lib/floresta")
      machine.succeed("stat -c '%U' /var/lib/floresta | grep -q floresta")

      # Verify ExecStart contains expected flags
      cmd = machine.succeed("systemctl show floresta.service -p ExecStart")
      assert "--network signet" in cmd, f"Expected --network signet in: {cmd}"
      assert "--debug" in cmd, f"Expected --debug in: {cmd}"
      assert "--rpc-address" in cmd, f"Expected --rpc-address in: {cmd}"
      assert "--electrum-address" in cmd, f"Expected --electrum-address in: {cmd}"

      # Verify hardening options are applied
      no_new_privs = machine.succeed("systemctl show floresta.service -p NoNewPrivileges")
      assert "yes" in no_new_privs, f"Expected NoNewPrivileges=yes, got: {no_new_privs}"

      protect_system = machine.succeed("systemctl show floresta.service -p ProtectSystem")
      assert "strict" in protect_system, f"Expected ProtectSystem=strict, got: {protect_system}"
    '';
  };
in
test
