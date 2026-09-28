# SPDX-License-Identifier: MIT OR Apache-2.0
#
# A mkFloresta module that builds Floresta for one Android ABI: it sets
# buildPhase, installPhase, extraEnvVars and extraBuildInputs from the
# distro's `pkgs` and `rustTarget`, which mkFlorestaDistro.nix hands every
# mkFloresta module as arguments. A distro imports it:
#   mkFloresta = ./patches/android-patches.nix;
#
# Android is not a nixpkgs cross set: host pkgs plus the NDK, cargo driven
# with --target and the NDK linker. This avoids the NDK version mismatch in
# nixpkgs' cross stdenv bootstrap. Only x86_64-linux can drive it: the
# prebuilt toolchain below is the linux-x86_64 one, and nixpkgs'
# androidndk-pkgs does not map aarch64 build hosts at all.
#
# Requires libbitcoinkernel-sys >= 0.3.0, whose build.rs drives cmake with
# the NDK's android.toolchain.cmake to build libbitcoinkernel for the target
# ABI.
{
  lib,
  pkgs,
  rustTarget,
  ...
}:

let
  # The Android SDK and NDK are unfree and need their license accepted; only
  # this instance of nixpkgs says so, not the one every other build uses.
  ndkVersion = "27.2.12479018";
  androidSdk =
    (
      (import pkgs.path {
        inherit (pkgs.stdenv.hostPlatform) system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      }).androidenv.composeAndroidPackages
      {
        platformVersions = [ "34" ];
        ndkVersions = [ ndkVersion ];
        includeNDK = true;
      }
    ).androidsdk;

  ndk = "${androidSdk}/libexec/android-sdk/ndk/${ndkVersion}";
  ndkToolchain = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64";

  # NDK clang triple: armv7 uses "armv7a-linux-androideabi",
  # all others match the Rust target triple.
  ndkClangTriple =
    if lib.hasPrefix "armv7" rustTarget then "armv7a-linux-androideabi" else rustTarget;
  ndkClang = "${ndkToolchain}/bin/${ndkClangTriple}24-clang";

  # Wrapper around the NDK clang that works around an armv7
  # compiler_builtins issue.  The pre-compiled libcompiler_builtins
  # for armv7-linux-androideabi ships ARM EABI symbols tagged with
  # @@LIBC_N (e.g. __aeabi_memcpy@@LIBC_N).  When lld links a
  # shared library it errors on symbols whose version node (LIBC_N)
  # is not defined — unless the symbol has local visibility.
  # Passing --exclude-libs,ALL marks every symbol pulled from
  # static archives as local, which suppresses the error.
  #
  # libbitcoinkernel-sys' build.rs emits the same flag, but cargo
  # applies a dependency's rustc-link-arg only to that crate's own
  # link targets — never to florestad / floresta-cli / libfloresta.
  ndkLinker = pkgs.writeShellScript "ndk-clang-wrapper" ''
    exec ${ndkClang} "-Wl,--exclude-libs,ALL" "$@"
  '';

  envTriple = builtins.replaceStrings [ "-" ] [ "_" ] rustTarget;
in
{
  # Explicit cargo build with --target so all crates (including
  # proc-macro / build-script crates) are compiled correctly.
  # $cargoBuildFlags is set by buildRustPackage from the packageSet.
  buildPhase = ''
    runHook preBuild
    cargo build \
      $cargoBuildFlags \
      --target ${rustTarget} \
      --offline \
      --release
    runHook postBuild
  '';

  # Install binaries / libraries from the target-specific output dir.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    local _releaseDir=target/${rustTarget}/release
    for bin in florestad floresta-cli; do
      if [ -f "$_releaseDir/$bin" ]; then
        cp "$_releaseDir/$bin" $out/bin/
      fi
    done
    for lib in "$_releaseDir"/libfloresta*.a "$_releaseDir"/libfloresta*.so; do
      if [ -f "$lib" ]; then
        cp "$lib" $out/lib/
      fi
    done
    runHook postInstall
  '';

  extraEnvVars = {
    ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
    ANDROID_NDK_HOME = ndk;
    ANDROID_NDK_ROOT = ndk;
    CARGO_BUILD_TARGET = rustTarget;
    "CARGO_TARGET_${lib.toUpper envTriple}_LINKER" = ndkLinker;

    # Tell the `cc` crate (used by secp256k1-sys etc.) to use the NDK
    # clang and llvm-ar for C code compiled for the Android target.
    # Without this, cc::Build picks the host compiler and produces
    # x86_64 object files that the aarch64/armv7 linker rejects.
    "CC_${envTriple}" = ndkClang;
    "AR_${envTriple}" = "${ndkToolchain}/bin/llvm-ar";
  };

  extraBuildInputs = [ androidSdk ];
}
