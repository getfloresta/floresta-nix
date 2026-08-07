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
                  ./lib/android-outputs.nix
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
          // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            service-vm-test = import ./lib/floresta-service-vm-test.nix {
              inherit pkgs;
              flakeInputs = inputs;
            };
          };

          packages =
            let
              inherit (pkgs) lib;

              # Upstream Floresta source — pinned via flake input, shared by
              # default builds, master builds, and Android cross-compilation.
              # Update with: nix flake update floresta-master
              masterSrc = inputs.floresta-master;

              # Build every Floresta variant from one source tree.
              mkVersionedBuild =
                src:
                import ./lib/floresta-build.nix {
                  inherit pkgs;
                  defaultSrc = src;
                };

              fetchTag =
                rev: hash:
                pkgs.fetchFromGitHub {
                  owner = "getfloresta";
                  repo = "Floresta";
                  inherit rev hash;
                };

              masterBuild = mkVersionedBuild masterSrc;

              # Sources for upstream release tags.  Attribute names become
              # the package suffix (florestad-v0_9_1, ...).
              taggedSrcs = {
                v0_9_1 = fetchTag "v0.9.1" "sha256-5dfE0Bd0yCDh7Kc0PsSXjBWLQ9WmNCCbropdXfK9YSk=";
                v0_9_0 = fetchTag "v0.9.0" "sha256-8GXCHvk6xxT93c073W15L0+xpri8lQvIcIdDcPead8I=";
              };

              # Versioned builds from upstream release tags (native only).
              # These use libbitcoinkernel-sys 0.2.0 which requires bindgen
              # and builds Bitcoin Core from source.
              taggedPackages = lib.concatMapAttrs (
                version: src:
                lib.mapAttrs' (name: lib.nameValuePair "${name}-${version}") (
                  lib.getAttrs [
                    "florestad"
                    "floresta-cli"
                    "libfloresta"
                  ] (mkVersionedBuild src)
                )
              ) taggedSrcs;
            in
            {
              # Native packages — built from the floresta-master flake input
              # (android_patched_bitcoinkernel branch).
              inherit (masterBuild)
                florestad
                floresta-cli
                libfloresta
                floresta-debug
                default
                ;
            }
            // taggedPackages
            # Android outputs: cross-compiled Floresta binaries and
            # libraries. See lib/android-outputs.nix.
            // import ./lib/android-outputs.nix {
              inherit
                pkgs
                inputs
                system
                masterSrc
                ;
            };

          formatter = pkgs.nixfmt-classic;

          devShells.default = pkgs.mkShell {
            inherit (self'.checks.nix-sanity-check) shellHook;
            packages = with pkgs; [
              nil
              nixfmt
              just
              nix-output-monitor
              cachix
            ];
          };
        };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-parts.url = "github:hercules-ci/flake-parts";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
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
