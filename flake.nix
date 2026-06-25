# SPDX-License-Identifier: MIT OR Apache-2.0

{
  description = "Nix & Flake packaging support for the Floresta node and library";

  nixConfig = {
    extra-substituters = [ "https://floresta-flake.cachix.org" ];
    extra-trusted-public-keys = [
      "floresta-flake.cachix.org-1:FIb3n6oyT4vr8Fc4TvJNADQB/PFTHzB376Ho1P8xxP8="
    ];
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = supportedSystems;

      flake = {
        nixosModules = {
          floresta = import ./lib/floresta-service.nix;
          default = inputs.self.nixosModules.floresta;
        };
      };

      perSystem =
        {
          pkgs,
          system,
          self',
          ...
        }:
        {
          _module.args.pkgs = import inputs.nixpkgs { inherit system; };

          checks = {
            nix-sanity-check = inputs.pre-commit-hooks.lib.${system}.run {
              src = pkgs.lib.fileset.toSource {
                root = ./.;
                fileset = pkgs.lib.fileset.unions [
                  ./lib/floresta-build.nix
                  ./lib/floresta-service.nix
                  ./lib/floresta-service-eval-test.nix
                  ./lib/floresta-service-vm-test.nix
                  ./flake.nix
                  ./flake.lock
                ];
              };
              hooks = {
                nixfmt.enable = true;
                deadnix.enable = true;
                nil.enable = true;
                statix.enable = true;
              };
            };

            service-eval-test = import ./lib/floresta-service-eval-test.nix {
              inherit pkgs;
              flakeInputs = inputs;
            };
          }
          // pkgs.lib.optionalAttrs pkgs.hostPlatform.isLinux {
            service-vm-test = import ./lib/floresta-service-vm-test.nix {
              inherit pkgs;
              flakeInputs = inputs;
            };
          };

          packages =
            let
              # Upstream Floresta source — pinned via flake input, shared by
              # default builds, master builds, and Android cross-compilation.
              # Update with: nix flake update floresta-master
              masterSrc = inputs.floresta-master;

              # Output hashes for git dependencies in the patched branch's
              # Cargo.lock (bitcoinkernel + libbitcoinkernel-sys from the
              # android_support branch of rust-bitcoinkernel).
              masterOutputHashes = {
                "bitcoinkernel-0.2.1" = "sha256-8h5ZON0j3gS2wppaJKj4vvyIAwhBRXXMcqNyrdhmd0k=";
                "libbitcoinkernel-sys-0.3.0" = "sha256-8h5ZON0j3gS2wppaJKj4vvyIAwhBRXXMcqNyrdhmd0k=";
              };

              florestaBuild = import ./lib/floresta-build.nix {
                inherit pkgs;
                defaultSrc = masterSrc;
                cargoLockOutputHashes = masterOutputHashes;
              };

              # Helper to build Floresta from a specific upstream tag/rev.
              mkVersionedBuild =
                { rev, hash }:
                import ./lib/floresta-build.nix {
                  inherit pkgs;
                  defaultSrc = pkgs.fetchFromGitHub {
                    owner = "getfloresta";
                    repo = "Floresta";
                    inherit rev hash;
                  };
                };

              v0_9_1 = mkVersionedBuild {
                rev = "v0.9.1";
                hash = "sha256-5dfE0Bd0yCDh7Kc0PsSXjBWLQ9WmNCCbropdXfK9YSk=";
              };
              v0_9_0 = mkVersionedBuild {
                rev = "v0.9.0";
                hash = "sha256-8GXCHvk6xxT93c073W15L0+xpri8lQvIcIdDcPead8I=";
              };

              # nixpkgs' androidndk-pkgs only supports x86_64 build hosts;
              # aarch64-darwin and aarch64-linux are not mapped.
              ndkSupported = system == "x86_64-linux" || system == "x86_64-darwin";
            in
            {
              # Native packages — built from the floresta-master flake input
              # (android_patched_bitcoinkernel branch).
              inherit (florestaBuild)
                florestad
                floresta-cli
                libfloresta
                floresta-debug
                default
                ;

              # Versioned builds from upstream release tags (native only).
              # These use libbitcoinkernel-sys 0.2.0 which requires bindgen
              # and builds Bitcoin Core from source.
              florestad-v0_9_1 = v0_9_1.florestad;
              floresta-cli-v0_9_1 = v0_9_1.floresta-cli;
              libfloresta-v0_9_1 = v0_9_1.libfloresta;

              florestad-v0_9_0 = v0_9_0.florestad;
              floresta-cli-v0_9_0 = v0_9_0.floresta-cli;
              libfloresta-v0_9_0 = v0_9_0.libfloresta;

              # Prebuilt libbitcoinkernel.a bundle for Android targets.
              # Collects the three per-target .a files from rust-bitcoinkernel
              # into a stable layout so consumers can link without building
              # Bitcoin Core from source. See PLATFORMS.md for consumer docs.
              android-prebuilt = pkgs.runCommand "libbitcoinkernel-android-prebuilt" { } ''
                mkdir -p $out/aarch64 $out/armv7 $out/x86_64
                cp ${
                  inputs.rust-bitcoinkernel.packages.${system}.android-aarch64
                }/lib/libbitcoinkernel.a $out/aarch64/
                cp ${inputs.rust-bitcoinkernel.packages.${system}.android-armv7}/lib/libbitcoinkernel.a $out/armv7/
                cp ${
                  inputs.rust-bitcoinkernel.packages.${system}.android-x86_64
                }/lib/libbitcoinkernel.a $out/x86_64/
                printf '%s\n' "${inputs.rust-bitcoinkernel.rev or "dirty"}" > $out/REV
              '';

              # Individual prebuilt libbitcoinkernel.a per target
              android-prebuilt-aarch64 = inputs.rust-bitcoinkernel.packages.${system}.android-aarch64;
              android-prebuilt-armv7 = inputs.rust-bitcoinkernel.packages.${system}.android-armv7;
              android-prebuilt-x86_64 = inputs.rust-bitcoinkernel.packages.${system}.android-x86_64;
            }
            # Cross-compiled Floresta for Android — requires NDK cross
            # toolchain, which nixpkgs only supports on x86_64 hosts.
            // pkgs.lib.optionalAttrs ndkSupported (
              let
                androidAarch64Build =
                  florestaBuild.mkAndroidBuild inputs.nixpkgs inputs.fenix.packages.${system} system
                    "aarch64-linux-android"
                    masterSrc
                    {
                      prebuiltLibbitcoinkernel = inputs.rust-bitcoinkernel.packages.${system}.android-aarch64;
                      cargoLockOutputHashes = masterOutputHashes;
                    };
                androidArmv7aBuild =
                  florestaBuild.mkAndroidBuild inputs.nixpkgs inputs.fenix.packages.${system} system
                    "armv7-linux-androideabi"
                    masterSrc
                    {
                      prebuiltLibbitcoinkernel = inputs.rust-bitcoinkernel.packages.${system}.android-armv7;
                      cargoLockOutputHashes = masterOutputHashes;
                    };
              in
              {
                florestad-aarch64-android = androidAarch64Build.florestad;
                floresta-cli-aarch64-android = androidAarch64Build.floresta-cli;
                libfloresta-aarch64-android = androidAarch64Build.libfloresta;

                florestad-armv7a-android = androidArmv7aBuild.florestad;
                floresta-cli-armv7a-android = androidArmv7aBuild.floresta-cli;
                libfloresta-armv7a-android = androidArmv7aBuild.libfloresta;
              }
            );

          formatter = pkgs.nixfmt-classic;

          devShells.default = pkgs.mkShell {
            inherit (self'.checks.nix-sanity-check) shellHook;
            packages = with pkgs; [
              nil
              nixfmt-classic
              just
              nix-output-monitor
              cachix
            ];
          };
        };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-parts.url = "github:hercules-ci/flake-parts";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-bitcoinkernel = {
      url = "github:jaoleal/rust-bitcoinkernel/android_support";
    };

    # Upstream Floresta with patched libbitcoinkernel-sys (>= 0.3.0).
    # Used for default native builds and Android cross-compilation.
    # Update with: nix flake update floresta-master
    floresta-master = {
      url = "github:jaoleal/FlorestaBA/android_patched_bitcoinkernel";
      flake = false;
    };
  };
}
