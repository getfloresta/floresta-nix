# SPDX-License-Identifier: MIT OR Apache-2.0

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  defaultSrc ? null,
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
              rev = "40524e239bc25b8df12f3e1fde3028f768da40f7";
              owner = "jaoleal";
              repo = "FlorestaBA";
              hash = "sha256-Ij2bCOJEoetaZtsHYN4gvtftpBs5E6b0IRXbjZ58V4k=";
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
      darwinFrameworks =
        with pkgs.darwin.apple_sdk.frameworks;
        [
          Security
          SystemConfiguration
        ]
        ++ [ pkgs.libiconv ];

      # Windows libraries and headers linked into the target binary.
      # mingw_w64_pthreads provides both libpthread and pthread.h (needed by aws-lc-sys).
      # mcfgthreads is the MCF thread model runtime that GCC 14+ links into
      # libgcc_eh; without it the linker fails with undefined __MCF_* symbols.
      windowsLibs = [
        pkgs.windows.mingw_w64_pthreads
        pkgs.windows.mcfgthreads
      ];

      inherit (pkgs.stdenv) targetPlatform;
    in
    pkgs.rustPlatform.buildRustPackage {
      inherit (cargoToml.package) version;
      inherit (pkgConfig) pname description cargoBuildFlags;
      inherit (cfg) src doCheck;

      buildFeatures = cfg.features ++ (cfg.extraFeatures or [ ]);

      # Build-time tools that run on the build machine
      nativeBuildInputs = [
        pkgs.buildPackages.pkg-config
        pkgs.buildPackages.cmake
        pkgs.buildPackages.llvmPackages.clang
        pkgs.buildPackages.llvmPackages.libclang
        pkgs.buildPackages.boost
      ]
      ++ lib.optionals pkgs.stdenv.buildPlatform.isDarwin [
        pkgs.buildPackages.libiconv
        pkgs.buildPackages.darwin.apple_sdk.frameworks.Security
        pkgs.buildPackages.darwin.apple_sdk.frameworks.SystemConfiguration
      ]
      ++ cfg.extraBuildInputs;

      # Libraries and frameworks linked into the target binary
      buildInputs =
        lib.optionals targetPlatform.isDarwin darwinFrameworks
        ++ lib.optionals targetPlatform.isWindows windowsLibs;

      cargoLock = {
        lockFile = "${cfg.src}/Cargo.lock";
      };

      LIBCLANG_PATH = "${pkgs.buildPackages.llvmPackages.libclang.lib}/lib";

      # bindgen (used by libbitcoinkernel-sys) invokes libclang to parse C
      # headers.  In cross-compilation the clang resource directory (which
      # contains compiler-provided headers like stddef.h) is not on the
      # default search path.  Point bindgen at it explicitly.
      # The resource dir lives in clang.cc.lib under lib/clang/<major>/include.
      BINDGEN_EXTRA_CLANG_ARGS = "-I${pkgs.buildPackages.llvmPackages.clang.cc.lib}/lib/clang/${lib.versions.major (lib.getVersion pkgs.buildPackages.llvmPackages.clang)}/include";

      # libbitcoinkernel-sys runs CMake on the build machine; point it at
      # the build-platform Boost so find_package(Boost) succeeds without
      # trying to cross-compile Boost for the target.
      CMAKE_PREFIX_PATH = "${pkgs.buildPackages.boost.dev}";

      # aws-lc-sys invokes CMake internally which doesn't inherit Nix's
      # cross-compilation include paths. Export the mingw pthreads headers
      # so CMake can find <pthread.h>, and suppress a GCC 14 false-positive
      # stringop-overflow warning in aws-lc's OPENSSL_memcpy.
      CFLAGS_x86_64_pc_windows_gnu = lib.optionalString targetPlatform.isWindows "-I${pkgs.windows.mingw_w64_pthreads}/include -Wno-error=stringop-overflow";

      # GCC 14+ on mingw uses the MCF thread model; libgcc_eh depends on
      # mcfgthread symbols.  Tell rustc to link the library explicitly.
      CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS = lib.optionalString targetPlatform.isWindows "-L native=${pkgs.windows.mcfgthreads}/lib -l static=mcfgthread";

      preBuild =
        let
          inherit (pkgs.stdenv) buildPlatform;
          isCross = pkgs.stdenv.hostPlatform != buildPlatform;
          # Nix cc-wrapper mangles NIX_LDFLAGS with the platform config
          platformSuffix = builtins.replaceStrings [ "-" ] [ "_" ] buildPlatform.config;
          # Map Nix kernel names to CMake system names
          cmakeSystemName =
            if targetPlatform.isWindows then
              "Windows"
            else if targetPlatform.isLinux then
              "Linux"
            else if targetPlatform.isDarwin then
              "Darwin"
            else
              toString targetPlatform.parsed.kernel.name;
          # Map Nix CPU names to CMake processor names
          cmakeSystemProcessor =
            if targetPlatform.isx86_64 then
              "x86_64"
            else if targetPlatform.isAarch64 then
              "aarch64"
            else
              toString targetPlatform.parsed.cpu.name;
        in
        # libbitcoinkernel-sys and aws-lc-sys invoke cmake directly from
        # build.rs without cross-compilation flags.  Write a CMake toolchain
        # file and wrap the cmake binary so that every configure invocation
        # (those containing "-S") automatically uses it.  A toolchain file
        # is more robust than individual -D flags because CMake reads it
        # before detecting the build platform, preventing it from looking
        # for host-specific tools like install_name_tool on Darwin.
        lib.optionalString isCross ''
                    mkdir -p $TMPDIR/cmake-wrap/bin

                    cat > $TMPDIR/cmake-cross-toolchain.cmake <<EOF
          set(CMAKE_SYSTEM_NAME ${cmakeSystemName})
          set(CMAKE_SYSTEM_PROCESSOR ${cmakeSystemProcessor})
          EOF

                    real_cmake="$(command -v cmake)"
                    cat > $TMPDIR/cmake-wrap/bin/cmake <<EOF
          #!/usr/bin/env bash
          # If this is a configure invocation (has -S flag), inject the
          # cross-compilation toolchain file.
          for arg in "\$@"; do
            if [ "\$arg" = "-S" ]; then
              exec $real_cmake -DCMAKE_TOOLCHAIN_FILE=$TMPDIR/cmake-cross-toolchain.cmake "\$@"
            fi
          done
          exec $real_cmake "\$@"
          EOF
                    chmod +x $TMPDIR/cmake-wrap/bin/cmake
                    export PATH="$TMPDIR/cmake-wrap/bin:$PATH"
        ''
        + lib.optionalString (buildPlatform.isDarwin && isCross) ''
          export NIX_LDFLAGS_${platformSuffix}="-L${pkgs.buildPackages.libiconv}/lib $NIX_LDFLAGS_${platformSuffix}"
        '';

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
    let
      suffix = if pkgs.stdenv.targetPlatform.isWindows then ".exe" else "";
    in
    pkgs.runCommand binName { inherit (combined) meta; } ''
      mkdir -p $out/bin
      cp ${combined}/bin/${binName}${suffix} $out/bin/${binName}${suffix}
    '';

  # Helper for cross-compilation: create package builders with a specific pkgs instance.
  # Builds all binaries once and splits them to avoid redundant compilation.
  forPkgs =
    targetPkgs:
    let
      florestaPkgs = import ./floresta-build.nix {
        pkgs = targetPkgs;
        inherit (targetPkgs) lib;
        inherit defaultSrc;
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
