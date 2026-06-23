# SPDX-License-Identifier: MIT OR Apache-2.0

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  defaultSrc ? null,
  # Extra output hashes for git dependencies in Cargo.lock (e.g. patched crates)
  cargoLockOutputHashes ? { },
  # Extra environment variables set on buildRustPackage (e.g. ANDROID_NDK_HOME)
  extraEnvVars ? { },
  # Extra native build inputs added to every build (e.g. Android SDK)
  extraNativeBuildInputsGlobal ? [ ],
  # Path to a prebuilt libbitcoinkernel.a — when set, a cargo override is
  # written so that libbitcoinkernel-sys's build.rs is skipped entirely.
  prebuiltLibbitcoinkernel ? null,
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

        cargoLock = {
          lockFile = "${cfg.src}/Cargo.lock";
        }
        // lib.optionalAttrs (cargoLockOutputHashes != { }) {
          outputHashes = cargoLockOutputHashes;
        };

        # libbitcoinkernel-sys runs CMake on the build machine; point it at
        # the build-platform Boost so find_package(Boost) succeeds without
        # trying to cross-compile Boost for the target.
        CMAKE_PREFIX_PATH = "${pkgs.buildPackages.boost.dev}";

        # bindgen (used by libbitcoinkernel-sys <= 0.2.0) needs libclang.
        LIBCLANG_PATH = "${pkgs.buildPackages.llvmPackages.libclang.lib}/lib";

      }
      # When a prebuilt libbitcoinkernel.a is provided, tell build.rs to
      # skip the CMake build and link the prebuilt library directly.
      // lib.optionalAttrs (prebuiltLibbitcoinkernel != null) {
        LIBBITCOINKERNEL_LIB_DIR = "${prebuiltLibbitcoinkernel}/lib";
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

        cargoDeps = rustPlatform.importCargoLock (
          {
            lockFile = "${cfg.src}/Cargo.lock";
          }
          // lib.optionalAttrs (cargoLockOutputHashes != { }) {
            outputHashes = cargoLockOutputHashes;
          }
        );

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

  # Android NDK configuration.
  # Requires libbitcoinkernel-sys >= 0.3.0 (no bindgen, supports
  # LIBBITCOINKERNEL_LIB_DIR to skip the CMake build entirely).
  # The Floresta source is passed in by the caller (flake.nix).
  androidConfig = {
    platformVersions = [ "34" ];
    ndkVersion = "27.2.12479018";
  };

  # Build Floresta for Android by cross-compiling through Cargo's --target
  # flag and the NDK linker, without using nixpkgs' crossSystem machinery.
  # This avoids the NDK version mismatch in nixpkgs' cross stdenv bootstrap.
  #
  # nixpkgsImport: the raw nixpkgs input (not an imported pkgs set)
  # system: the build host system string (must be x86_64-linux or x86_64-darwin)
  # rustTarget: Rust target triple (e.g. "aarch64-linux-android")
  # src: Floresta source tree (must use libbitcoinkernel-sys >= 0.3.0)
  mkAndroidBuild =
    nixpkgsImport: fenixPkgs: system: rustTarget: src:
    {
      prebuiltLibbitcoinkernel ? null,
      cargoLockOutputHashes ? { },
    }:
    let
      nativePkgs = import nixpkgsImport {
        inherit system;
        config.android_sdk.accept_license = true;
        config.allowUnfree = true;
      };
      composition = nativePkgs.androidenv.composeAndroidPackages {
        inherit (androidConfig) platformVersions;
        ndkVersions = [ androidConfig.ndkVersion ];
        includeNDK = true;
      };
      sdk = composition.androidsdk;
      ndk = "${sdk}/libexec/android-sdk/ndk/${androidConfig.ndkVersion}";

      # Build a Rust toolchain that includes rust-std for the Android
      # target.  Without this, rustc can't find `core` / `std` for the
      # cross target.
      rustToolchain = fenixPkgs.combine [
        fenixPkgs.stable.rustc
        fenixPkgs.stable.cargo
        fenixPkgs.stable.rust-src
        fenixPkgs.stable.rust-std
        fenixPkgs.targets.${rustTarget}.stable.rust-std
      ];
      androidRustPlatform = nativePkgs.makeRustPlatform {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };

      # NDK clang triple: armv7 uses "armv7a-linux-androideabi",
      # all others match the Rust target triple.
      ndkClangTriple =
        if builtins.match "armv7.*" rustTarget != null then "armv7a-linux-androideabi" else rustTarget;

      ndkToolchain = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64";
      ndkClang = "${ndkToolchain}/bin/${ndkClangTriple}24-clang";

      # Wrapper around the NDK clang that strips --no-undefined-version.
      # Rust >= 1.80 injects -Wl,--no-undefined-version into all Android
      # link invocations, but compiler_builtins for armv7 ships symbols
      # tagged with @@LIBC_N which NDK 27's lld doesn't define.  The
      # wrapper rewrites --no-undefined-version → --undefined-version so
      # those references become warnings instead of errors.
      ndkLinker = nativePkgs.writeShellScript "ndk-clang-wrapper" ''
        args=()
        for arg in "$@"; do
          if [ "$arg" = "--no-undefined-version" ]; then
            args+=("--undefined-version")
          else
            args+=("$arg")
          fi
        done
        exec ${ndkClang} "''${args[@]}"
      '';

      # Cargo env var prefix for the target (e.g. CARGO_TARGET_AARCH64_LINUX_ANDROID)
      cargoTargetPrefix = "CARGO_TARGET_${
        builtins.replaceStrings [ "-" ] [ "_" ] (nativePkgs.lib.toUpper rustTarget)
      }";
    in
    import ./floresta-build.nix {
      pkgs = nativePkgs;
      inherit (nativePkgs) lib;
      inherit prebuiltLibbitcoinkernel cargoLockOutputHashes;
      defaultSrc = src;
      rustPlatform = androidRustPlatform;

      # Disable the default cargoBuildHook / cargoInstallHook — they
      # don't handle cross-compilation via --target properly.
      dontCargoBuild = true;

      # Explicit cargo build with --target so all crates (including
      # proc-macro / build-script crates) are compiled correctly.
      # $cargoBuildFlags is set by buildRustPackage from the Nix attribute.
      customBuildPhase = ''
        runHook preBuild
        cargo build \
          $cargoBuildFlags \
          --target ${rustTarget} \
          --offline \
          --release
        runHook postBuild
      '';

      # Install binaries / libraries from the target-specific output dir.
      customInstallPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/lib
        local _releaseDir=target/${rustTarget}/release
        # Copy binaries (florestad, floresta-cli)
        for bin in florestad floresta-cli; do
          if [ -f "$_releaseDir/$bin" ]; then
            cp "$_releaseDir/$bin" $out/bin/
          fi
        done
        # Copy libraries (libfloresta)
        for lib in "$_releaseDir"/libfloresta*.a "$_releaseDir"/libfloresta*.so; do
          if [ -f "$lib" ]; then
            cp "$lib" $out/lib/
          fi
        done
        runHook postInstall
      '';

      extraEnvVars = {
        ANDROID_HOME = "${sdk}/libexec/android-sdk";
        ANDROID_NDK_HOME = ndk;
        ANDROID_NDK_ROOT = ndk;
        CARGO_BUILD_TARGET = rustTarget;
        "${cargoTargetPrefix}_LINKER" = ndkLinker;

        # Tell the `cc` crate (used by secp256k1-sys etc.) to use the NDK
        # clang and llvm-ar for C code compiled for the Android target.
        # Without this, cc::Build picks the host compiler and produces
        # x86_64 object files that the aarch64/armv7 linker rejects.
        "CC_${builtins.replaceStrings [ "-" ] [ "_" ] rustTarget}" = ndkClang;
        "AR_${builtins.replaceStrings [ "-" ] [ "_" ] rustTarget}" = "${ndkToolchain}/bin/llvm-ar";
      };
      extraNativeBuildInputsGlobal = [ sdk ];
    };

in
{
  inherit
    mkFloresta
    buildFlorestaOptions
    androidConfig
    mkAndroidBuild
    ;

  default = mkFloresta { };
  florestad = mkFloresta { packageName = "florestad"; };
  floresta-cli = mkFloresta { packageName = "floresta-cli"; };
  libfloresta = mkFloresta { packageName = "libfloresta"; };
  floresta-debug = mkFloresta { packageName = "floresta-debug"; };
}
