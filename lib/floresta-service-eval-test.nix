# SPDX-License-Identifier: MIT OR Apache-2.0

# Evaluation-based tests for floresta-service.nix
# Verifies that every NixOS option correctly maps to CLI flags in ExecStart.
# Works on all platforms (no VM required).
{ pkgs, flakeInputs }:

let
  inherit (pkgs) lib;

  # Dummy package to satisfy the package option without building floresta
  dummyPkg = pkgs.runCommand "floresta-dummy" { } ''
    mkdir -p $out/bin
    cat > $out/bin/florestad <<'EOF'
    #!/bin/sh
    echo "dummy florestad"
    EOF
    chmod +x $out/bin/florestad
  '';

  # Helper: evaluate the floresta module with given service config
  evalFloresta =
    serviceCfg:
    let
      evaluated = flakeInputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          flakeInputs.self.nixosModules.floresta
          {
            services.floresta = {
              enable = true;
              package = dummyPkg;
            }
            // serviceCfg;

            # Minimal config to make nixosSystem evaluate
            boot.loader.grub.devices = [ "nodev" ];
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.05";
          }
        ];
      };
    in
    evaluated.config;

  # Helper: get ExecStart from evaluated config
  getExecStart =
    serviceCfg: (evalFloresta serviceCfg).systemd.services.floresta.serviceConfig.ExecStart;

  # Helper: get full service config
  getServiceConfig = serviceCfg: (evalFloresta serviceCfg).systemd.services.floresta.serviceConfig;

  # Helper: check if assertion would fail
  assertionFails =
    serviceCfg:
    let
      cfg = evalFloresta serviceCfg;
      failedAssertions = builtins.filter (a: !a.assertion) cfg.assertions;
    in
    failedAssertions != [ ];

  # --- Test cases ---
  # Each test is a { name, expr } where expr must evaluate to true

  tests = {
    # Default options
    defaults-has-network-bitcoin = {
      expr = builtins.match ".*--network bitcoin.*" (getExecStart { }) != null;
    };

    defaults-has-data-dir = {
      expr = builtins.match ".*--data-dir.*/var/lib/floresta.*" (getExecStart { }) != null;
    };

    defaults-no-debug = {
      expr = builtins.match ".*--debug.*" (getExecStart { }) == null;
    };

    defaults-no-no-cfilters = {
      expr = builtins.match ".*--no-cfilters.*" (getExecStart { }) == null;
    };

    defaults-no-no-assume-utreexo = {
      expr = builtins.match ".*--no-assume-utreexo.*" (getExecStart { }) == null;
    };

    defaults-no-no-backfill = {
      expr = builtins.match ".*--no-backfill.*" (getExecStart { }) == null;
    };

    # Boolean flags that enable CLI args
    debug-flag = {
      expr =
        builtins.match ".*--debug.*" (getExecStart {
          debug = true;
        }) != null;
    };

    log-to-file-flag = {
      expr =
        builtins.match ".*--log-to-file.*" (getExecStart {
          logToFile = true;
        }) != null;
    };

    disable-dns-seeds-flag = {
      expr =
        builtins.match ".*--disable-dns-seeds.*" (getExecStart {
          disableDnsSeeds = true;
        }) != null;
    };

    allow-v1-fallback-flag = {
      expr =
        builtins.match ".*--allow-v1-fallback.*" (getExecStart {
          allowV1Fallback = true;
        }) != null;
    };

    # Boolean flags that disable defaults (--no-* pattern)
    no-cfilters-flag = {
      expr =
        builtins.match ".*--no-cfilters.*" (getExecStart {
          cfilters = false;
        }) != null;
    };

    no-assume-utreexo-flag = {
      expr =
        builtins.match ".*--no-assume-utreexo.*" (getExecStart {
          assumeUtreexo = false;
        }) != null;
    };

    no-backfill-flag = {
      expr =
        builtins.match ".*--no-backfill.*" (getExecStart {
          backfill = false;
        }) != null;
    };

    # String/value options
    assume-valid-custom = {
      expr =
        builtins.match ".*--assume-valid.*" (getExecStart {
          assumeValid = "0";
        }) != null;
    };

    assume-valid-hardcoded-absent = {
      expr =
        builtins.match ".*--assume-valid.*" (getExecStart {
          assumeValid = "hardcoded";
        }) == null;
    };

    proxy-flag = {
      expr =
        builtins.match ".*--proxy 127.0.0.1:9050.*" (getExecStart {
          proxy = "127.0.0.1:9050";
        }) != null;
    };

    connect-flag = {
      expr =
        builtins.match ".*--connect 10.0.0.1:8333.*" (getExecStart {
          connect = "10.0.0.1:8333";
        }) != null;
    };

    filters-start-height-flag = {
      expr =
        builtins.match ".*--filters-start-height -1000.*" (getExecStart {
          filtersStartHeight = -1000;
        }) != null;
    };

    network-signet = {
      expr =
        builtins.match ".*--network signet.*" (getExecStart {
          network = "signet";
        }) != null;
    };

    network-regtest = {
      expr =
        builtins.match ".*--network regtest.*" (getExecStart {
          network = "regtest";
        }) != null;
    };

    # Server address options
    rpc-address-flag = {
      expr =
        builtins.match ".*--rpc-address 127.0.0.1:8332.*" (getExecStart {
          rpc.address = "127.0.0.1:8332";
        }) != null;
    };

    electrum-address-flag = {
      expr =
        builtins.match ".*--electrum-address 127.0.0.1:50001.*" (getExecStart {
          electrum.address = "127.0.0.1:50001";
        }) != null;
    };

    electrum-tls-enable-flag = {
      expr =
        builtins.match ".*--enable-electrum-tls.*" (getExecStart {
          electrum.tls.enable = true;
        }) != null;
    };

    electrum-tls-address-flag = {
      expr =
        builtins.match ".*--electrum-address-tls 127.0.0.1:50002.*" (getExecStart {
          electrum.tls.address = "127.0.0.1:50002";
        }) != null;
    };

    generate-cert-flag = {
      expr =
        builtins.match ".*--generate-cert.*" (getExecStart {
          electrum.tls.generateCert = true;
        }) != null;
    };

    zmq-address-flag = {
      expr =
        builtins.match ".*--zmq-address tcp://127.0.0.1:29000.*" (getExecStart {
          zmqAddress = "tcp://127.0.0.1:29000";
        }) != null;
    };

    # List options
    wallet-xpubs-flag = {
      expr =
        builtins.match ".*--wallet-xpub xpub1.*--wallet-xpub xpub2.*" (getExecStart {
          walletXpubs = [
            "xpub1"
            "xpub2"
          ];
        }) != null;
    };

    wallet-descriptors-flag = {
      expr =
        builtins.match ".*--wallet-descriptor 'wpkh.*'.*" (getExecStart {
          walletDescriptors = [ "wpkh(key)" ];
        }) != null;
    };

    # Extra args
    extra-args = {
      expr =
        builtins.match ".*--custom-flag.*" (getExecStart {
          extraArgs = [ "--custom-flag" ];
        }) != null;
    };

    # systemd service config
    user-default = {
      expr = (getServiceConfig { }).User == "floresta";
    };

    group-default = {
      expr = (getServiceConfig { }).Group == "floresta";
    };

    user-custom = {
      expr = (getServiceConfig { user = "btcnode"; }).User == "btcnode";
    };

    # Assertion: electrum without cfilters should fail
    electrum-requires-cfilters = {
      expr = assertionFails {
        electrum.address = "127.0.0.1:50001";
        cfilters = false;
      };
    };
  };

  # Run all tests and collect failures
  testResults = lib.mapAttrsToList (
    name: test:
    let
      passed = builtins.tryEval test.expr;
    in
    {
      inherit name;
      ok = passed.success && passed.value;
      error =
        if !passed.success then
          "evaluation error"
        else if !passed.value then
          "assertion failed"
        else
          null;
    }
  ) tests;

  failures = builtins.filter (r: !r.ok) testResults;
  failureMessages = map (r: "  FAIL: ${r.name} (${r.error})") failures;
  passCount = builtins.length (builtins.filter (r: r.ok) testResults);
  totalCount = builtins.length testResults;
in
pkgs.runCommand "floresta-service-eval-test"
  {
    passthru = { inherit tests testResults failures; };
  }
  (
    if failures == [ ] then
      ''
        echo "All ${toString totalCount} floresta service eval tests passed."
        mkdir $out
        echo "PASS: ${toString totalCount}/${toString totalCount}" > $out/results.txt
      ''
    else
      ''
        echo "Floresta service eval tests: ${toString passCount}/${toString totalCount} passed"
        echo ""
        echo "Failures:"
        ${lib.concatStringsSep "\n" (map (msg: ''echo "${msg}"'') failureMessages)}
        echo ""
        exit 1
      ''
  )
