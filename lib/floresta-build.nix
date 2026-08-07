# SPDX-License-Identifier: MIT OR Apache-2.0

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  defaultSrc ? null,
  # Extra environment variables set on buildRustPackage (e.g. ANDROID_NDK_HOME)
  extraEnvVars ? { },
  # Extra native build inputs added to every build (e.g. Android SDK)
  extraNativeBuildInputsGlobal ? [ ],
  # When true, disable cargoBuildHook and use customBuildPhase instead.
  # Required for Android cross-compilation where cargo must be invoked
  # with an explicit --target flag.
  dontCargoBuild ? false,
  # Custom buildPhase used when dontCargoBuild is true (e.g. Android).
  customBuildPhase ? null,
  # Custom installPhase used when dontCargoBuild is true (e.g. Android).
  customInstallPhase ? null,
  # Override the Rust platform (rustc + cargo + rust-std).  Defaults to
  # pkgs.rustPlatform.  For Android cross-compilation a fenix-based
  # platform with the target's rust-std must be supplied.
  rustPlatform ? pkgs.rustPlatform,
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
        default =
          if defaultSrc != null then
            defaultSrc
          else
            pkgs.fetchFromGitHub {
              owner = "getfloresta";
              repo = "Floresta";
              rev = "v0.9.1";
              hash = "sha256-5dfE0Bd0yCDh7Kc0PsSXjBWLQ9WmNCCbropdXfK9YSk=";
            };
        description = ''
          Source tree for the Floresta project.

          By default, fetches the latest master branch from GitHub.
          Can be overridden to use a local checkout or specific revision.
        '';
        example = ''
          pkgs.fetchFromGitHub {
            owner = "getfloresta";
            repo = "Floresta";
            rev = "v0.9.1";
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
        default = false;
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
      darwinFrameworks =
        with pkgs.darwin.apple_sdk.frameworks;
        [
          Security
          SystemConfiguration
        ]
        ++ [ pkgs.libiconv ];

      inherit (pkgs.stdenv) targetPlatform;
    in
    rustPlatform.buildRustPackage (
      {
        inherit (cargoToml.package) version;
        inherit (pkgConfig) pname description cargoBuildFlags;
        inherit (cfg) src doCheck;

        buildFeatures = cfg.features ++ (cfg.extraFeatures or [ ]);

        # Build-time tools that run on the build machine
        nativeBuildInputs = [
          pkgs.buildPackages.pkg-config
          pkgs.buildPackages.cmake
          pkgs.buildPackages.boost
          pkgs.buildPackages.llvmPackages.clang
          pkgs.buildPackages.llvmPackages.libclang
        ]
        ++ lib.optionals pkgs.stdenv.buildPlatform.isDarwin [
          pkgs.buildPackages.libiconv
          pkgs.buildPackages.darwin.apple_sdk.frameworks.Security
          pkgs.buildPackages.darwin.apple_sdk.frameworks.SystemConfiguration
        ]
        ++ extraNativeBuildInputsGlobal
        ++ cfg.extraBuildInputs;

        # Libraries and frameworks linked into the target binary
        buildInputs = lib.optionals targetPlatform.isDarwin darwinFrameworks;

        # Cargo.lock pins libbitcoinkernel-sys to a git rev, which carries no
        # checksum.  Let builtins.fetchGit vendor it from the pinned rev
        # instead of hardcoding an outputHash that goes stale every time
        # upstream bumps the dependency.
        cargoLock = {
          lockFile = "${cfg.src}/Cargo.lock";
          allowBuiltinFetchGit = true;
        };

        # libbitcoinkernel-sys runs CMake on the build machine; point it at
        # the build-platform Boost so find_package(Boost) succeeds without
        # trying to cross-compile Boost for the target.
        CMAKE_PREFIX_PATH = "${pkgs.buildPackages.boost.dev}";

        # bindgen (used by libbitcoinkernel-sys <= 0.2.0) needs libclang.
        LIBCLANG_PATH = "${pkgs.buildPackages.llvmPackages.libclang.lib}/lib";

      }
      # When cross-compiling (e.g. Android), disable the default cargo
      # build/install hooks and use explicit phases with --target.
      // lib.optionalAttrs dontCargoBuild {
        inherit dontCargoBuild;
        dontCargoInstall = true;
      }
      // lib.optionalAttrs (customBuildPhase != null) {
        buildPhase = customBuildPhase;
      }
      // lib.optionalAttrs (customInstallPhase != null) {
        installPhase = customInstallPhase;
      }
      // {

        preBuild =
          let
            inherit (pkgs.stdenv) buildPlatform;
            isCross = pkgs.stdenv.hostPlatform != buildPlatform;
            platformSuffix = builtins.replaceStrings [ "-" ] [ "_" ] buildPlatform.config;
          in
          lib.optionalString (buildPlatform.isDarwin && isCross) ''
            export NIX_LDFLAGS_${platformSuffix}="-L${pkgs.buildPackages.libiconv}/lib $NIX_LDFLAGS_${platformSuffix}"
          '';

        cargoDeps = rustPlatform.importCargoLock {
          lockFile = "${cfg.src}/Cargo.lock";
          allowBuiltinFetchGit = true;
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
          "--skip=p2p_wire::node::conn::tests::test_parse_address"
        ];

        meta = with lib; {
          description = "A lightweight bitcoin full node - ${pkgConfig.description}";
          homepage = "https://github.com/getfloresta/Floresta";
          license = with licenses; [
            mit
            asl20
          ];
          maintainers = with maintainers; [ jaoleal ];
          platforms = platforms.unix;
          mainProgram = pkgConfig.pname;
        };

        passthru = {
          inherit cfg pkgConfig;
          override = newArgs: mkFloresta (cfg // newArgs);
          overrideAttrs = f: (mkFloresta args).overrideAttrs f;
        };
      }
      // extraEnvVars
    );

in
{
  inherit mkFloresta buildFlorestaOptions;

  default = mkFloresta { };
  florestad = mkFloresta { packageName = "florestad"; };
  floresta-cli = mkFloresta { packageName = "floresta-cli"; };
  libfloresta = mkFloresta { packageName = "libfloresta"; };
  floresta-debug = mkFloresta { packageName = "floresta-debug"; };
}
