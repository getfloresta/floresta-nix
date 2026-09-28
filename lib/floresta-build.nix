# SPDX-License-Identifier: MIT OR Apache-2.0

{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  # Source tree every build defaults to; standalone imports fall back to
  # the v0.9.1 tag.  Fetched at evaluation time rather than by a
  # derivation: the version is read off its Cargo.toml, and a derivation
  # cannot be built under `nix flake check --no-build`.
  defaultSrc ? builtins.fetchTarball {
    url = "https://github.com/getfloresta/Floresta/archive/v0.9.1.tar.gz";
    sha256 = "sha256-5dfE0Bd0yCDh7Kc0PsSXjBWLQ9WmNCCbropdXfK9YSk=";
  },
  # Override the Rust platform (rustc + cargo + rust-std).  Defaults to
  # pkgs.rustPlatform.  A cross build must supply one whose toolchain
  # carries the target's rust-std (android-outputs.nix does).
  rustPlatform ? pkgs.rustPlatform,
  # Appended to every package name produced by this import, to tell cross
  # variants apart in the store: an Android import passes "-aarch64-android"
  # and gets `floresta-aarch64-android`.
  pnameSuffix ? "",
}:

let
  inherit (lib) types mkOption;

  # Option definitions for the build module
  buildFlorestaOptions = {
    options = {
      packageSet = mkOption {
        type = types.nonEmptyListOf (types.enum componentNames);
        default = [
          "florestad"
          "floresta-cli"
        ];
        description = ''
          The binaries and libraries to build, in one cargo invocation.

          - `florestad`: the Floresta Node
          - `floresta-cli`: the CLI tool
          - `libfloresta`: the Floresta library (every lib target of the
            workspace)
        '';
        example = [ "libfloresta" ];
      };

      profile = mkOption {
        type = types.enum [
          "release"
          "debug"
        ];
        default = "release";
        description = ''
          Cargo profile to build with.

          `debug` keeps assertions and debug info, at the cost of a much
          slower binary.  Ignored by cross builds that drive cargo through a
          custom build phase.
        '';
        example = "debug";
      };

      src = mkOption {
        type = types.path;
        default = defaultSrc;
        description = ''
          Source tree for the Floresta project.

          Defaults to whatever the import was given as `defaultSrc` — the
          v0.9.1 tag, for a standalone import. Can be overridden to
          use a local checkout or specific revision.
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
          Inputs to be included during build time of floresta (e.g. the
          Android SDK).
        '';
      };

      extraEnvVars = mkOption {
        type = types.attrsOf (types.either types.str types.package);
        default = { };
        description = ''
          Environment variables set on the build (e.g. ANDROID_NDK_HOME).
        '';
      };

      buildPhase = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Replaces the cargo build hook. For targets cargo must be driven by
          hand, with an explicit `--target` (e.g. Android); `$cargoBuildFlags`
          carries the packageSet.
        '';
      };

      installPhase = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Replaces the cargo install hook, which only knows the host's
          target directory.
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

  # What each packageSet entry adds to the cargo invocation.  `isBin` marks
  # the ones a package can be run as.  `componentNames` orders them: the
  # first selected one names the package, and the first binary is the one
  # it runs as.
  componentNames = [
    "florestad"
    "floresta-cli"
    "libfloresta"
  ];
  components = {
    florestad = {
      cargoBuildFlags = [
        "--bin"
        "florestad"
      ];
      description = "Floresta Node";
      cargoTomlPath = "bin/florestad/Cargo.toml";
      isBin = true;
    };

    floresta-cli = {
      cargoBuildFlags = [
        "--bin"
        "floresta-cli"
      ];
      description = "Floresta CLI";
      cargoTomlPath = "bin/floresta-cli/Cargo.toml";
      isBin = true;
    };

    libfloresta = {
      cargoBuildFlags = [ "--lib" ];
      description = "Floresta library";
      cargoTomlPath = "crates/floresta/Cargo.toml";
      isBin = false;
    };
  };

  # Main builder function
  mkFloresta =
    args:
    let
      cfg = evalConfig args;

      # The packageSet in the order of componentNames, duplicates dropped.
      selected = lib.filter (c: lib.elem c cfg.packageSet) componentNames;
      first = components.${lib.head selected};
      cargoToml = builtins.fromTOML (builtins.readFile "${cfg.src}/${first.cargoTomlPath}");
      mainProgram = lib.findFirst (c: components.${c}.isBin) null selected;
      description = lib.concatMapStringsSep ", " (c: components.${c}.description) selected;

      # Darwin libraries linked into the target binary.  The frameworks
      # (Security, SystemConfiguration) come with the Darwin stdenv's
      # `apple-sdk`.
      darwinInputs = [ pkgs.libiconv ];

      inherit (pkgs.stdenv) targetPlatform;
    in
    rustPlatform.buildRustPackage (
      {
        inherit (cargoToml.package) version;
        inherit (cfg) src doCheck;
        inherit description;
        cargoBuildFlags = lib.concatMap (c: components.${c}.cargoBuildFlags) selected;

        # The profile is part of the name: a debug build of a release is a
        # different derivation of the same version, and two store paths that
        # differ only by a hash are not worth telling apart by hand.
        pname =
          (if lib.length selected == 1 then lib.head selected else "floresta")
          + pnameSuffix
          + lib.optionalString (cfg.profile != "release") "-${cfg.profile}";
        buildType = cfg.profile;
        buildFeatures = cfg.features;

        # Build-time tools that run on the build machine
        nativeBuildInputs = [
          pkgs.buildPackages.pkg-config
          pkgs.buildPackages.cmake
          pkgs.buildPackages.boost
          pkgs.buildPackages.llvmPackages.clang
          pkgs.buildPackages.llvmPackages.libclang
        ]
        ++ lib.optionals pkgs.stdenv.buildPlatform.isDarwin [ pkgs.buildPackages.libiconv ]
        ++ cfg.extraBuildInputs;

        # Libraries linked into the target binary
        buildInputs = lib.optionals targetPlatform.isDarwin darwinInputs;

        # A Cargo.lock may pin a dependency to a git rev, which carries no
        # checksum.  Let builtins.fetchGit vendor it from the pinned rev
        # instead of hardcoding an outputHash that goes stale every time it
        # is bumped.
        cargoLock = {
          lockFile = "${cfg.src}/Cargo.lock";
          allowBuiltinFetchGit = true;
        };

        # libbitcoinkernel-sys runs CMake on the build machine; point it at
        # the build-platform Boost so find_package(Boost) succeeds without
        # trying to cross-compile Boost for the target.  Fine while the
        # kernel uses Boost header-only: should a version link a boost_*
        # library, this must become pkgs.boost, spliced for the target.
        CMAKE_PREFIX_PATH = "${pkgs.buildPackages.boost.dev}";

        # bindgen (used by libbitcoinkernel-sys <= 0.2.0) needs libclang.
        LIBCLANG_PATH = "${pkgs.buildPackages.llvmPackages.libclang.lib}/lib";

      }
      # A phase given by hand (e.g. Android, cargo with --target) replaces
      # the cargo hook for it.
      // lib.optionalAttrs (cfg.buildPhase != null) {
        inherit (cfg) buildPhase;
        dontCargoBuild = true;
      }
      // lib.optionalAttrs (cfg.installPhase != null) {
        inherit (cfg) installPhase;
        dontCargoInstall = true;
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

        meta =
          with lib;
          {
            description = "A lightweight bitcoin full node - ${description}";
            homepage = "https://github.com/getfloresta/Floresta";
            license = with licenses; [
              mit
              asl20
            ];
            maintainers = with maintainers; [ jaoleal ];
            platforms = platforms.unix;
          }
          # A library has no binary to be run as.
          // lib.optionalAttrs (mainProgram != null) { inherit mainProgram; };

        passthru = {
          inherit cfg;
          override = newArgs: mkFloresta (cfg // newArgs);
        };
      }
      // cfg.extraEnvVars
    );

in
{
  inherit mkFloresta buildFlorestaOptions;

  # The default packageSet — florestad and floresta-cli — from one cargo
  # invocation, so the shared dependency graph (libbitcoinkernel included)
  # compiles once; the install hook sorts what it leaves into bin/ and lib/.
  default = mkFloresta { };

  debug = mkFloresta { profile = "debug"; };
}
