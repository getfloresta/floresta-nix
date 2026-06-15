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
                  ./contrib/floresta-attest
                  ./contrib/floresta-verify
                  ./contrib/import-keys.sh
                ];
              };
              hooks = {
                nixfmt.enable = true;
                deadnix.enable = true;
                nil.enable = true;
                statix.enable = true;
                shellcheck.enable = true;
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
              florestaBuild = import ./lib/floresta-build.nix { inherit pkgs; };
              crossX86 = florestaBuild.forPkgs pkgs.pkgsCross.gnu64;
              crossAarch64 = florestaBuild.forPkgs pkgs.pkgsCross.aarch64-multiplatform;
              mingwPkgs = import inputs.nixpkgs {
                inherit system;
                crossSystem.config = "x86_64-w64-mingw32";
                overlays = florestaBuild.mingwOverlays;
              };
              crossWindows = florestaBuild.forPkgs mingwPkgs;

              # Android cross-compilation is x86_64-only: nixpkgs'
              # androidndk-pkgs doesn't support aarch64-darwin as a build
              # host (missing from ndkBuildInfoFun), and the free LLVM
              # path has bootstrap issues (compiler-rt, bionic-prebuilt).
              # TODO: upstream a nixpkgs PR adding aarch64-apple-darwin
              # to androidndk-pkgs.nix ndkBuildInfoFun.
              androidAarch64Build =
                florestaBuild.mkAndroidBuild inputs.nixpkgs system
                  pkgs.lib.systems.examples.aarch64-android-prebuilt;
              androidArmv7aBuild =
                florestaBuild.mkAndroidBuild inputs.nixpkgs system
                  pkgs.lib.systems.examples.armv7a-android-prebuilt;
            in
            {
              # Native packages — available on all systems
              inherit (florestaBuild)
                florestad
                floresta-cli
                libfloresta
                floresta-debug
                default
                ;
            }
            // pkgs.lib.optionalAttrs (system != "x86_64-linux") {
              # Cross-compiled x86_64-linux from any other host
              florestad-x86_64-linux = crossX86.florestad;
              floresta-cli-x86_64-linux = crossX86.floresta-cli;
            }
            // pkgs.lib.optionalAttrs (system != "aarch64-linux") {
              # Cross-compiled aarch64-linux from any other host
              florestad-aarch64-linux = crossAarch64.florestad;
              floresta-cli-aarch64-linux = crossAarch64.floresta-cli;
            }
            // {
              # Cross-compiled Windows x86_64 from any host
              florestad-x86_64-windows = crossWindows.florestad;
              floresta-cli-x86_64-windows = crossWindows.floresta-cli;
            }
            // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
              # Cross-compiled Android — x86_64 hosts only.
              # nixpkgs' androidndk-pkgs doesn't support aarch64-darwin
              # build hosts yet (NDK ships universal macOS binaries but
              # nixpkgs hasn't added the platform mapping).

              # Android aarch64 (arm64-v8a)
              florestad-aarch64-android = androidAarch64Build.florestad;
              floresta-cli-aarch64-android = androidAarch64Build.floresta-cli;
              libfloresta-aarch64-android = androidAarch64Build.libfloresta;

              # Android armv7a (armeabi-v7a)
              florestad-armv7a-android = androidArmv7aBuild.florestad;
              floresta-cli-armv7a-android = androidArmv7aBuild.floresta-cli;
              libfloresta-armv7a-android = androidArmv7aBuild.libfloresta;
            };

          formatter = pkgs.nixfmt-classic;

          devShells.default = pkgs.mkShell {
            inherit (self'.checks.nix-sanity-check) shellHook;
            packages = with pkgs; [
              nil
              nixfmt-classic
              just
              shellcheck
              shfmt
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
  };
}
