# SPDX-License-Identifier: MIT OR Apache-2.0

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:

let
  inherit (lib) types mkOption;

  # Option definitions for the build module
  buildFlorestaOptions = {
    options = {
      packageName = mkOption {
        type = types.enum [
          "all"
          "libfloresta"
          "florestad"
          "floresta-cli"
          "floresta-debug"
        ];
        default = "all";
        description = ''
          Which floresta package variant to build.

          - `all`: Builds all components (CLI, Node and lib)
          - `libfloresta`: Only the Floresta library
          - `florestad`: Only the Floresta Node
          - `floresta-cli`: Only the CLI tool
          - `floresta-debug`: CLI and Node with Debug profile
        '';
        example = "florestad";
      };

      src = mkOption {
        type = types.path;
        default = pkgs.fetchFromGitHub {
          rev = "eb03116ed513c22297c1d4bc8d07a71c44de00af";
          owner = "vinteumorg";
          repo = "floresta";
          hash = "sha256-2efto4VWT7satrQoWSsg0YDWZlVDgvMNLEHrN+UUbGY=";
        };
        description = ''
          Source tree for the Floresta project.

          By default, fetches the latest master branch from GitHub.
          Can be overridden to use a local checkout or specific revision.
        '';
        example = ''
          pkgs.fetchFromGitHub {
            owner = "vinteumorg";
            repo = "floresta";
            rev = "v0.5.0";
            hash = "sha256-... ";
          }
        '';
      };

      features = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Additional cargo features to enable during build.

          These are passed directly to `cargo build --features`.

          The examples shows all feature options, including Node and Libraries features.
        '';
        example = [
          "zmq-server"
          "metricss"
          "tokio-console"
          "experimental"
          "json-rpc"
          "bitcoinconsensus"
          "test-utils"
          "flat-chainstore"
          "std"
          "descriptors-std"
          "descriptors-no-std"
          "clap"
          "bitcoinconsensus"
          "watch-only-wallet"
          "memory-database"
        ];
      };

      extraBuildInputs = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = ''
          Inputs to be included during build time of floresta.
        '';
      };

      doCheck = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to run tests during the build, deactivate if youre limited on resources.

          Only offline tests are executed.
        '';
      };
    };
  };

  # Evaluate the module to get the final configuration
  evalConfig =
    config:
    let
      evaluated = lib.evalModules {
        modules = [
          buildFlorestaOptions
          { inherit config; }
        ];
      };
    in
    evaluated.config;

  # Package-specific configurations
  packageConfigs = {
    all = {
      pname = "floresta";
      cargoBuildFlags = [ ];
      description = "Floresta packages, CLI and Node";
      cargoTomlPath = "bin/florestad/Cargo.toml";
    };

    libfloresta = {
      pname = "libfloresta";
      cargoBuildFlags = [ "--lib" ];
      description = "Floresta library";
      cargoTomlPath = "crates/floresta/Cargo.toml";
    };

    florestad = {
      pname = "florestad";
      cargoBuildFlags = [
        "--bin"
        "florestad"
      ];
      description = "Floresta Node";
      cargoTomlPath = "bin/florestad/Cargo.toml";
    };

    floresta-cli = {
      pname = "floresta-cli";
      cargoBuildFlags = [
        "--bin"
        "floresta-cli"
      ];
      description = "Floresta CLI";
      cargoTomlPath = "bin/floresta-cli/Cargo.toml";
    };

    floresta-debug = {
      pname = "floresta-debug";
      cargoBuildFlags = [ ];
      description = "Floresta in debug profile";
      cargoTomlPath = "bin/florestad/Cargo.toml";
      extraFeatures = [ "metrics" ];
    };
  };

  # Main builder function
  mkFloresta =
    args:
    let
      cfg = evalConfig args;
      pkgConfig = packageConfigs.${cfg.packageName};
      cargoToml = builtins.fromTOML (builtins.readFile "${cfg.src}/${pkgConfig.cargoTomlPath}");

      # Darwin frameworks linked into the target binary
      darwinFrameworks = with pkgs.darwin.apple_sdk.frameworks; [
        Security
        SystemConfiguration
      ];

      # Windows libraries linked into the target binary
      windowsLibs = [ pkgs.windows.pthreads ];

      inherit (pkgs.stdenv) targetPlatform;
    in
    pkgs.rustPlatform.buildRustPackage {
      inherit (cargoToml.package) version;
      inherit (pkgConfig) pname description cargoBuildFlags;
      inherit (cfg) src doCheck;

      buildFeatures = cfg.features ++ (cfg.extraFeatures or [ ]);

      # Build-time tools that run on the build machine
      nativeBuildInputs = [
        pkgs.pkg-config
        pkgs.cmake
        pkgs.llvmPackages.clang
        pkgs.llvmPackages.libclang
      ]
      ++ cfg.extraBuildInputs;

      # Libraries and frameworks linked into the target binary
      buildInputs = [
        pkgs.openssl
        pkgs.boost
      ]
      ++ lib.optionals targetPlatform.isDarwin darwinFrameworks
      ++ lib.optionals targetPlatform.isWindows windowsLibs;

      cargoLock = {
        lockFile = "${cfg.src}/Cargo.lock";
      };

      LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
      CMAKE_PREFIX_PATH = "${pkgs.boost.dev}";

      cargoDeps = pkgs.rustPlatform.importCargoLock {
        lockFile = "${cfg.src}/Cargo.lock";
      };

      checkFlags = [
        "--skip=tests::test_get_block_header"
        "--skip=tests::test_get_block"
        "--skip=tests::test_get_block_hash"
        "--skip=tests::test_get_best_block_hash"
        "--skip=tests::test_get_blockchaininfo"
        "--skip=tests::test_stop"
        "--skip=tests::test_get_roots"
        "--skip=tests::test_get_height"
        "--skip=tests::test_send_raw_transaction"
        "--skip=p2p_wire::node::tests::test_parse_address"
      ];

      meta = with lib; {
        description = "A lightweight bitcoin full node - ${pkgConfig.description}";
        homepage = "https://github.com/vinteumorg/Floresta";
        license = with licenses; [
          mit
          asl20
        ];
        maintainers = with maintainers; [ jaoleal ];
        platforms = platforms.unix ++ platforms.windows;
        mainProgram = pkgConfig.pname;
      };

      passthru = {
        inherit cfg pkgConfig;
        override = newArgs: mkFloresta (cfg // newArgs);
        overrideAttrs = f: (mkFloresta args).overrideAttrs f;
      };
    };

  # Extract a single binary from a combined build
  extractBin =
    combined: binName:
    pkgs.runCommand binName { inherit (combined) meta; } ''
      mkdir -p $out/bin
      cp ${combined}/bin/${binName} $out/bin/${binName}
    '';

  # Helper for cross-compilation: create package builders with a specific pkgs instance.
  # Builds all binaries once and splits them to avoid redundant compilation.
  forPkgs =
    targetPkgs:
    let
      florestaPkgs = import ./floresta-build.nix {
        pkgs = targetPkgs;
        inherit (targetPkgs) lib;
      };
      combined = florestaPkgs.mkFloresta {
        packageName = "all";
        doCheck = false;
      };
    in
    {
      inherit (florestaPkgs) mkFloresta;
      default = combined;
      florestad = florestaPkgs.extractBin combined "florestad";
      floresta-cli = florestaPkgs.extractBin combined "floresta-cli";
      libfloresta = florestaPkgs.mkFloresta {
        packageName = "libfloresta";
        doCheck = false;
      };
      floresta-debug = florestaPkgs.mkFloresta {
        packageName = "floresta-debug";
        doCheck = false;
      };
    };
in
{
  inherit
    mkFloresta
    forPkgs
    extractBin
    buildFlorestaOptions
    ;

  default = mkFloresta { };
  florestad = mkFloresta { packageName = "florestad"; };
  floresta-cli = mkFloresta { packageName = "floresta-cli"; };
  libfloresta = mkFloresta { packageName = "libfloresta"; };
  floresta-debug = mkFloresta { packageName = "floresta-debug"; };
}
