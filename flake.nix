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

      pkgsFor =
        system:
        import inputs.nixpkgs {
          inherit system;
          overlays = [ inputs.rust-overlay.overlays.default ];
        };

      # Every package each host builds, and the releases — see lib/targets.nix.
      targetsFor = system: import ./lib/targets.nix { pkgs = pkgsFor system; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = supportedSystems;

      flake = {
        nixosModules = {
          floresta = import ./lib/floresta-service.nix;
          default = inputs.self.nixosModules.floresta;
        };

        lib = {
          mkFlorestaDistro =
            system: (import ./lib/mkFlorestaDistro.nix { pkgs = pkgsFor system; }).mkFlorestaDistro;
          inherit targetsFor;
        };
      };

      perSystem =
        {
          pkgs,
          system,
          self',
          ...
        }:
        let
          # What this host builds — see lib/targets.nix.
          targets = targetsFor system;
          packages = targets.packages.${system} or { };

          # Release attestation — see lib/attestation.nix.
          attestation = import ./lib/attestation.nix {
            inherit pkgs packages;
            inherit (targets) releases;
            trustedKeys = ./contrib/trusted-keys;
            sigs = ./contrib/sigs;
          };
        in
        {
          _module.args.pkgs = pkgsFor system;

          checks = {
            nix-sanity-check = inputs.pre-commit-hooks.lib.${system}.run {
              src = pkgs.lib.fileset.toSource {
                root = ./.;
                fileset = pkgs.lib.fileset.unions [
                  ./lib/attestation.nix
                  ./lib/floresta-build.nix
                  ./lib/mkFlorestaDistro.nix
                  ./lib/patches/android-patches.nix
                  ./lib/targets.nix
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

            # The same verifier `nix run .#verify` runs, against what is
            # committed.
            attestations = attestation.check;
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            service-vm-test = import ./lib/floresta-service-vm-test.nix {
              inherit pkgs;
              flakeInputs = inputs;
            };
          };

          # The whole matrix this host builds, one package per (release,
          # distro).
          inherit packages;

          # The SHA256SUMS of one release, as this host builds it.
          legacyPackages.attestation-manifests = attestation.manifests;

          # The attestation verbs.
          apps = {
            verify.program = attestation.verify;
            attest.program = attestation.attest;
            releases.program = attestation.listReleases;
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

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
