# SPDX-License-Identifier: MIT OR Apache-2.0

{
  description = "Nix & Flake packaging support for the Floresta node and library";

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
            };

          devShells.default = pkgs.mkShell {
            inherit (self'.checks.nix-sanity-check) shellHook;
            packages = with pkgs; [
              nil
              nixfmt
              just
              shellcheck
              shfmt
              nix-output-monitor
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
