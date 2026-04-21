# SPDX-License-Identifier: MIT OR Apache-2.0

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib)
    concatMap
    concatStringsSep
    escapeShellArg
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.services.floresta;

  # Build the florestad command line from NixOS options
  florestadCmd = concatStringsSep " " (
    [
      "${cfg.package}/bin/florestad"
      "--network ${cfg.network}"
      "--data-dir ${escapeShellArg cfg.dataDir}"
    ]
    ++ optional cfg.debug "--debug"
    ++ optional cfg.logToFile "--log-to-file"
    ++ optional (!cfg.cfilters) "--no-cfilters"
    ++ optional (!cfg.assumeUtreexo) "--no-assume-utreexo"
    ++ optional (!cfg.backfill) "--no-backfill"
    ++ optional cfg.disableDnsSeeds "--disable-dns-seeds"
    ++ optional cfg.allowV1Fallback "--allow-v1-fallback"
    ++ optional (cfg.assumeValid != "hardcoded") "--assume-valid ${escapeShellArg cfg.assumeValid}"
    ++ optional (cfg.proxy != null) "--proxy ${escapeShellArg cfg.proxy}"
    ++ optional (cfg.connect != null) "--connect ${escapeShellArg cfg.connect}"
    ++ optional (
      cfg.filtersStartHeight != null
    ) "--filters-start-height ${toString cfg.filtersStartHeight}"
    ++ optional (cfg.rpc.address != null) "--rpc-address ${escapeShellArg cfg.rpc.address}"
    ++ optional (
      cfg.electrum.address != null
    ) "--electrum-address ${escapeShellArg cfg.electrum.address}"
    ++ optional cfg.electrum.tls.enable "--enable-electrum-tls"
    ++ optional (
      cfg.electrum.tls.address != null
    ) "--electrum-address-tls ${escapeShellArg cfg.electrum.tls.address}"
    ++ optional (
      cfg.electrum.tls.keyPath != null
    ) "--tls-key-path ${escapeShellArg cfg.electrum.tls.keyPath}"
    ++ optional (
      cfg.electrum.tls.certPath != null
    ) "--tls-cert-path ${escapeShellArg cfg.electrum.tls.certPath}"
    ++ optional cfg.electrum.tls.generateCert "--generate-cert"
    ++ optional (cfg.zmqAddress != null) "--zmq-address ${escapeShellArg cfg.zmqAddress}"
    ++ concatMap (x: [
      "--wallet-xpub"
      (escapeShellArg x)
    ]) cfg.walletXpubs
    ++ concatMap (x: [
      "--wallet-descriptor"
      (escapeShellArg x)
    ]) cfg.walletDescriptors
    ++ cfg.extraArgs
  );
in
{
  options.services.floresta = {
    enable = mkEnableOption "Floresta Bitcoin node daemon";

    allowV1Fallback = mkOption {
      type = types.bool;
      default = false;
      description = "Allow fallback to v1 P2P transport if v2 fails.";
    };

    assumeUtreexo = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use assume-utreexo mode for faster initial sync.
        Skips validation of early blocks using a trusted accumulator.
      '';
    };

    assumeValid = mkOption {
      type = types.str;
      default = "hardcoded";
      example = "00000000000000000002a7c4c1e48d76c5a37902165a270156b7a8d72728a054";
      description = ''
        Assume-valid configuration. Can be:
        - "hardcoded": use the built-in checkpoint (default)
        - "0": disable assume-valid
        - a block hash: assume blocks up to this hash have valid signatures
      '';
    };

    backfill = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Backfill and validate blocks skipped during assume-utreexo sync.
      '';
    };

    cfilters = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Build and store compact block filters (BIP 157/158).
        Required for the Electrum server and wallet rescanning.
      '';
    };

    connect = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.168.1.10:8333";
      description = "Connect only to this specific node.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/floresta";
      description = "Directory for chain and wallet data.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable verbose debug logging.";
    };

    disableDnsSeeds = mkOption {
      type = types.bool;
      default = false;
      description = "Disable DNS seed discovery for finding peers.";
    };

    electrum = {
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "127.0.0.1:50001";
        description = "Address for the Electrum server to listen on.";
      };

      tls = {
        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "127.0.0.1:50002";
          description = "Address for the Electrum TLS server.";
        };

        certPath = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to TLS certificate (PKCS#8 PEM).";
        };

        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable Electrum TLS server.";
        };

        generateCert = mkOption {
          type = types.bool;
          default = false;
          description = "Auto-generate a self-signed certificate.";
        };

        keyPath = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to TLS private key (PKCS#8 PEM).";
        };
      };
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--some-future-flag" ];
      description = "Extra command-line arguments to pass to florestad.";
    };

    filtersStartHeight = mkOption {
      type = types.nullOr types.int;
      default = null;
      example = -1000;
      description = ''
        Block height to start downloading filters from.
        Negative values are relative to the current tip.
      '';
    };

    group = mkOption {
      type = types.str;
      default = cfg.user;
      description = "Group under which floresta runs.";
    };

    logToFile = mkOption {
      type = types.bool;
      default = false;
      description = "Write logs to a file in the data directory.";
    };

    network = mkOption {
      type = types.enum [
        "bitcoin"
        "signet"
        "regtest"
      ];
      default = "bitcoin";
      description = "Which Bitcoin network to use.";
    };

    package = mkOption {
      type = types.package;
      default =
        pkgs.floresta
          or (throw "floresta package not found in pkgs. Provide one via services.floresta.package.");
      description = "The package providing florestad.";
    };

    proxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "127.0.0.1:9050";
      description = "SOCKS5 proxy for outgoing connections (e.g. Tor).";
    };

    rpc = {
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "127.0.0.1:8332";
        description = "Address for the JSON-RPC server (host:port).";
      };
    };

    user = mkOption {
      type = types.str;
      default = "floresta";
      description = "User account under which floresta runs.";
    };

    walletDescriptors = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Output descriptors to watch.";
    };

    walletXpubs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "SLIP-132-encoded extended public keys to watch.";
    };

    zmqAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "tcp://127.0.0.1:29000";
      description = "Address for the ZMQ push/pull server.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.electrum.address != null -> cfg.cfilters;
        message = "Electrum server requires compact block filters (cfilters) to be enabled.";
      }
    ];

    systemd.services.floresta = {
      description = "Floresta Bitcoin Node";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = florestadCmd;
        Restart = "on-failure";
        RestartSec = "30s";
        TimeoutStartSec = "10min";
        TimeoutStopSec = "10min";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        UMask = "0077";

        ReadWritePaths = [ cfg.dataDir ];
        MemoryDenyWriteExecute = true;
        LimitNOFILE = 8192;
      };
    };

    users = {
      groups.${cfg.group} = { };
      users.${cfg.user} = {
        inherit (cfg) group;
        isSystemUser = true;
        description = "Floresta daemon user";
        home = cfg.dataDir;
        createHome = true;
      };
    };
  };
}
