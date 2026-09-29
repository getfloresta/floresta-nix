# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Every package floresta-nix builds: packages.<host>.<name> is one distro of
# one release, as that host builds it. A host lists a distro only after that
# combination was built once, and from the first release it built from.
# Named florestad-<distro>-v<release>, dots as underscores so the name needs
# no quoting; mkFlorestaDistroForEachTag writes one per release it is given.
#
# A distro is dynamically linked unless its name says `-static`
# (x86_64-linux vs x86_64-linux-static). Only static binaries run outside
# Nix or NixOS: a dynamic one loads its interpreter and libraries from
# /nix/store.
#
# Imported with the host's pkgs, and only that host's entry is read: the
# pkgsCross sets below are relative to it. (release, distro, host) is the
# key an attestation signs.
{ pkgs }:

let
  inherit (pkgs) lib;
  inherit (import ./mkFlorestaDistro.nix { inherit pkgs; }) mkFlorestaDistroForEachTag;

  fetchTag =
    rev: hash:
    pkgs.fetchFromGitHub {
      owner = "jaoleal";
      repo = "FlorestaBA";
      inherit rev hash;
    };

  # Oldest first, so a range of releases is a slice of the list.
  releases = [
    {
      version = "0.9.0";
      src = fetchTag "v0.9.0" "sha256-8GXCHvk6xxT93c073W15L0+xpri8lQvIcIdDcPead8I=";
    }
    {
      version = "0.9.1";
      src = fetchTag "v0.9.1" "sha256-5dfE0Bd0yCDh7Kc0PsSXjBWLQ9WmNCCbropdXfK9YSk=";
    }
    {
      version = "0.10.0";
      src = fetchTag "v0.10.0-preview" "sha256-SCh1J33Ht4o7TIUdNdC6J3P6dSJd6YquvxAr0VIA5Og=";
    }
  ];

  # The releases from `version` on.
  releasesSince =
    version:
    lib.drop (lib.lists.findFirstIndex (
      release: release.version == version
    ) (throw "targets.nix: no release ${version}") releases) releases;
in
{
  inherit releases;

  packages = {
    x86_64-linux =
      mkFlorestaDistroForEachTag releases (release: {
        inherit release;
        name = "x86_64-linux";
        description = "Linux x86_64, dynamic (glibc)";
      })

      # ---- not built yet ----
      # The static-pie link fails: pkgsStatic's libstdc++.a (pulled in by
      # libbitcoinkernel-sys) is not built with -fPIE.
      # // mkFlorestaDistroForEachTag releases (release: {
      #   inherit release;
      #   name = "x86_64-linux-static";
      #   description = "Linux x86_64, static (musl)";
      #   pkgs = pkgs.pkgsCross.musl64.pkgsStatic;
      #   static = true;
      # })

      # Android builds from 0.10.0 on: the first release whose
      # libbitcoinkernel-sys cross-compiles for it.
      // mkFlorestaDistroForEachTag (releasesSince "0.10.0") (release: {
        inherit release;
        name = "aarch64-android";
        description = "Android arm64-v8a (NDK)";
        rustTarget = "aarch64-linux-android";
        mkFloresta = ./patches/android-patches.nix;
      })

    # ---- not built yet ----
    # // mkFlorestaDistroForEachTag (releasesSince "0.10.0") (release: {
    #   inherit release;
    #   name = "armv7a-android";
    #   description = "Android armeabi-v7a (NDK)";
    #   rustTarget = "armv7-linux-androideabi";
    #   mkFloresta = ./patches/android-patches.nix;
    # })
    # // mkFlorestaDistroForEachTag (releasesSince "0.10.0") (release: {
    #   inherit release;
    #   name = "x86_64-android";
    #   description = "Android x86_64, emulator (NDK)";
    #   rustTarget = "x86_64-linux-android";
    #   mkFloresta = ./patches/android-patches.nix;
    # })
    ;

    aarch64-linux = mkFlorestaDistroForEachTag releases (release: {
      inherit release;
      name = "aarch64-linux";
      description = "Linux aarch64, dynamic (glibc)";
    })

    # ---- not built yet ----
    # The static-pie link fails: pkgsStatic's libstdc++.a (pulled in by
    # libbitcoinkernel-sys) is not built with -fPIE.
    # // mkFlorestaDistroForEachTag releases (release: {
    #   inherit release;
    #   name = "x86_64-linux-static";
    #   description = "Linux x86_64, static (musl)";
    #   pkgs = pkgs.pkgsCross.musl64.pkgsStatic;
    #   static = true;
    # })
    ;

    aarch64-darwin = mkFlorestaDistroForEachTag releases (release: {
      inherit release;
      name = "aarch64-darwin";
      description = "macOS Apple Silicon";
    })

    # ---- not built yet ----
    # Prefer `extra-platforms = x86_64-darwin` in nix-darwin and a native
    # build under Rosetta (uses cache.nixos.org); pkgsCross.x86_64-darwin
    # is the fallback.
    # // mkFlorestaDistroForEachTag (releasesSince "0.10.0") (release: {
    #   inherit release;
    #   name = "x86_64-darwin";
    #   description = "macOS Intel";
    #   pkgs = pkgs.pkgsCross.x86_64-darwin;
    # })
    ;
  };
}
