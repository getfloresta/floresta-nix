# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Exports:
#   distroOptions    : module describing one distro of one release
#   mkFlorestaDistro : distro spec -> derivation, the spec validated against
#                      distroOptions (targets.nix writes them out)
#   mkFlorestaDistroForEachTag
#                    : releases -> (release -> distro spec) -> packages, one
#                      per release
#
# A distro is floresta-build specialised for one place to run. floresta-build
# decides WHAT is built; a distro decides WHERE, and carries the patches needed
# to get there.
{ pkgs }:

let
  inherit (pkgs) lib;
  inherit (lib) types mkOption;

  # Only the option set is read here; the build imports floresta-build again
  # with the cross package set.
  florestaBuildOptions = (import ./floresta-build.nix { inherit pkgs; }).buildFlorestaOptions;

  distroOptions =
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          description = "The distro, appended to the pname (`floresta-<name>`).";
          example = "x86_64-linux";
        };

        description = mkOption {
          type = types.str;
          description = "Appended to `meta.description`.";
          example = "Linux aarch64, static (musl)";
        };

        release = {
          version = mkOption {
            type = types.str;
            description = "The Floresta release built; names its attestation manifest.";
            example = "0.9.1";
          };
          src = mkOption {
            type = types.path;
            description = "The release's source tree.";
          };
        };

        pkgs = mkOption {
          type = types.pkgs;
          default = pkgs;
          defaultText = lib.literalExpression "pkgs";
          description = ''
            The package set the build runs in. The host's is a native build.
            Anything else must be a `pkgsCross.*` set, so that
            nativeBuildInputs and buildInputs are spliced by nixpkgs. Only
            read when the distro is built.
          '';
          example = lib.literalExpression "pkgs.pkgsCross.musl64.pkgsStatic";
        };

        static = mkOption {
          type = types.bool;
          default = false;
          description = "Require statically linked ELFs; enforced by an installCheck.";
        };

        rustTarget = mkOption {
          type = types.str;
          default = config.pkgs.stdenv.hostPlatform.rust.rustcTarget;
          defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.rust.rustcTarget";
          description = ''
            rustc target triple, derived from `pkgs`. Set it only when the
            target is not a nixpkgs cross set (e.g. Android).
          '';
          example = "aarch64-linux-android";
        };

        toolchain = mkOption {
          type = types.functionTo types.package;
          default =
            {
              src,
              pkgs',
              rustTarget,
            }:
            let
              rustBin = pkgs'.pkgsBuildHost.rust-bin;
              toolchainFile = "${src}/rust-toolchain.toml";
            in
            # Without a rust-toolchain.toml, the stable rustc the rust-overlay
            # lock pins.
            if builtins.pathExists toolchainFile then
              rustBin.fromRustupToolchain {
                inherit ((lib.importTOML toolchainFile).toolchain) channel;
                targets = [ rustTarget ];
              }
            else
              rustBin.stable.latest.minimal.override { targets = [ rustTarget ]; };
          defaultText = "rust-overlay toolchain from the release's rust-toolchain.toml (stable when absent), plus rust-std for rustTarget";
          description = ''
            `{ src, pkgs', rustTarget } -> toolchain`. Runs on the build platform
            and ships rust-std for the target, so nixpkgs' rustc is never rebuilt.
          '';
        };

        mkFloresta = mkOption {
          type = types.submodule [
            florestaBuildOptions
            # A patch module reads the distro's package set and triple as
            # module arguments, so a distro only imports it.
            { _module.args = { inherit (config) pkgs rustTarget; }; }
          ];
          default = { };
          description = ''
            Arguments to floresta-build's `mkFloresta`, validated against its
            own option set: what to build (packageSet, features, profile...)
            and the patches a target needs to get there (buildPhase,
            installPhase, extraEnvVars, extraBuildInputs). A patch is a
            module taking `pkgs` and `rustTarget`, given as the value itself
            — see patches/android-patches.nix. `src` is ignored: the release
            decides it.
          '';
          example = lib.literalExpression "./patches/android-patches.nix";
        };

        overrideAttrs = mkOption {
          type = types.functionTo types.attrs;
          default = _old: { };
          defaultText = lib.literalExpression "old: { }";
          description = "Final patch applied to the derivation. Escape hatch.";
        };
      };
    };

  mkFlorestaDistro =
    spec:
    let
      cfg =
        (lib.evalModules {
          modules = [
            distroOptions
            { config = spec; }
          ];
        }).config;
      pkgs' = cfg.pkgs;
      inherit (cfg) release rustTarget;
      toolchain = cfg.toolchain {
        inherit (release) src;
        inherit pkgs' rustTarget;
      };

      florestaBuild = import ./floresta-build.nix {
        pkgs = pkgs';
        rustPlatform = pkgs'.makeRustPlatform {
          cargo = toolchain;
          rustc = toolchain;
        };
        defaultSrc = release.src;
        pnameSuffix = "-${cfg.name}";
      };

      # The evaluated mkFloresta options carry floresta-build's default src;
      # the release's tree wins over it. `_module` is the
      # submodule's own bookkeeping, not an argument.
      drv = florestaBuild.mkFloresta (
        removeAttrs cfg.mkFloresta [ "_module" ] // { inherit (release) src; }
      );
    in
    (drv.overrideAttrs (old: {
      # nixpkgs skips installCheck when the build platform cannot run the
      # result (aarch64-linux building x86_64-linux), so the check only
      # guards builds from a host of the target's architecture.
      doInstallCheck = cfg.static;
      installCheckPhase = ''
        for bin in "$out"/bin/*; do
          ${pkgs'.pkgsBuildBuild.file}/bin/file "$bin" | grep -q "dynamically linked" \
            && { echo "$bin (${cfg.name}) must be static" >&2; exit 1; }
        done
      '';
      passthru = old.passthru // {
        distro = cfg;
        inherit release rustTarget;
      };
      meta = old.meta // {
        description = "${old.meta.description} — ${cfg.description}";
        # Where the build's host package set runs. For a nixpkgs cross set
        # that is the target; for Android (host pkgs + NDK) it is the build
        # host, since nixpkgs has no platform to check the NDK output against.
        platforms = [ pkgs'.stdenv.hostPlatform.system ];
      };
    })).overrideAttrs
      cfg.overrideAttrs;

  # One distro built from each of `releases`, as the packages targets.nix
  # names them: florestad-<distro>-v<release>, dots as underscores. `spec`
  # is a function of the release, so only the release differs between them.
  mkFlorestaDistroForEachTag =
    releases: spec:
    lib.listToAttrs (
      map (
        release:
        let
          distro = spec release;
        in
        lib.nameValuePair "florestad-${distro.name}-v${builtins.replaceStrings [ "." ] [ "_" ] release.version}" (
          mkFlorestaDistro distro
        )
      ) releases
    );
in
{
  inherit distroOptions mkFlorestaDistro mkFlorestaDistroForEachTag;
}
