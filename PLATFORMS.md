# Floresta Platform Support Matrix

## Artifacts

| Artifact         | Description                                                    |
| ---------------- | -------------------------------------------------------------- |
| `florestad`      | Full node daemon — the main binary                             |
| `floresta-cli`   | Command-line client for interacting with `florestad`           |
| `libfloresta`    | Shared library for embedding Floresta in other applications    |
| `floresta-debug` | Debug build of `florestad` (native only, never cross-compiled) |

---

## Build Matrix

The table below shows every `(host, target)` combination. **Host** is the
machine running `nix build`; **Target** is the platform the resulting binary
runs on.

| Target              | x86_64-linux | aarch64-linux | x86_64-darwin | aarch64-darwin |
| ------------------- | :----------: | :-----------: | :-----------: | :------------: |
| **x86_64-linux**    |    native    |     cross     |     cross     |     cross      |
| **aarch64-linux**   |    cross     |    native     |     cross     |     cross      |
| **x86_64-windows**  |    cross     |     cross     |     cross     |     cross      |
| **aarch64-android** |    cross     |       -       |     cross     |       -        |
| **armv7a-android**  |    cross     |       -       |     cross     |       -        |
| **x86_64-darwin**   |      -       |       -       |    native     |       -        |
| **aarch64-darwin**  |      -       |       -       |       -       |     native     |

> **native** = built and runs on the same platform.
> **cross** = cross-compiled from the host to a different target.
> **-** = not available from this host.

### Package availability per target

| Target          | `florestad` | `floresta-cli` | `libfloresta` | `floresta-debug` |
| --------------- | :---------: | :------------: | :-----------: | :--------------: |
| x86_64-linux    |     yes     |      yes       |      yes      |       yes        |
| aarch64-linux   |     yes     |      yes       |      yes      |       yes        |
| x86_64-windows  |     yes     |      yes       |       -       |        -         |
| aarch64-android |     yes     |      yes       |      yes      |        -         |
| armv7a-android  |     yes     |      yes       |      yes      |        -         |
| x86_64-darwin   |     yes     |      yes       |      yes      |       yes        |
| aarch64-darwin  |     yes     |      yes       |      yes      |       yes        |

---

## Quick Reference

Build a native package:

```bash
nix build .#florestad
```

Cross-compile (the suffix is the target):

```bash
nix build .#florestad-aarch64-linux
nix build .#florestad-x86_64-windows
nix build .#florestad-aarch64-android
```

Build everything your host can produce:

```bash
just cross-build-all
```

---

## Target Notes

### Linux (x86_64 / aarch64)

Fully supported as both host and target on all four build hosts. Linux
targets use the standard nixpkgs cross-compilation toolchain with
`pkgs.pkgsCross`. These are the most battle-tested targets.

### Windows (x86_64)

Cross-compiled via MinGW (`x86_64-w64-mingw32`). Available from every host.
Meson tests are disabled during cross-compilation because sandbox timeouts
cause spurious failures. Only `florestad` and `floresta-cli` are produced —
`libfloresta` is not built for Windows.

### Android (aarch64 / armv7a)

Cross-compiled using the Android NDK prebuilt toolchain. **Requires unfree
packages** (`config.allowUnfree = true`, scoped only to the Android pkgs
import) because the NDK is proprietary.

Android targets use a patched Floresta source tree that includes
`rust-bitcoinkernel` android support (from the `android_support` branch).
The CMake toolchain file sets `CMAKE_SYSTEM_NAME = Android` and injects the
appropriate API level so that `libbitcoinkernel-sys` and `aws-lc-sys` build
correctly.

**Host restriction:** Android targets are only available on **x86_64** hosts
(Linux and macOS). The nixpkgs `androidndk-pkgs` module does not list
`aarch64-apple-darwin` in its `ndkBuildInfoFun`, so the NDK toolchain cannot
be unpacked on Apple Silicon. A future nixpkgs PR could lift this
restriction.

### macOS (x86_64 / aarch64)

Native builds only — macOS targets cannot be cross-compiled from Linux due
to the proprietary Apple SDK. Each macOS architecture can only be built on
its own architecture (no x86_64-darwin from aarch64-darwin or vice versa)
since Rosetta and universal binaries are not wired into the Nix build.

---

## Attestation & Release

The `contrib/floresta-attest` script builds and attests all targets
reachable from the current host. The target list is system-aware:

| Host           | Attested targets                                                                            |
| -------------- | ------------------------------------------------------------------------------------------- |
| x86_64-linux   | x86_64-linux, aarch64-linux, x86_64-windows, aarch64-android, armv7a-android                |
| x86_64-darwin  | x86_64-linux, aarch64-linux, x86_64-darwin, x86_64-windows, aarch64-android, armv7a-android |
| aarch64-darwin | x86_64-linux, aarch64-linux, x86_64-windows, aarch64-darwin                                 |

---

## Known Limitations

1. **Android on Apple Silicon** — Blocked by nixpkgs. The NDK prebuilt
   toolchain only ships x86_64 host binaries in the nixpkgs packaging. The
   free LLVM cross-compilation path has bootstrap issues (`compiler-rt` and
   `bionic-prebuilt` circular dependencies). Tracked as a TODO for an
   upstream nixpkgs PR.

2. **Windows `libfloresta`** — Not produced. The shared library build has
   not been validated under MinGW.

3. **macOS cross-compilation** — Not possible from Linux hosts due to Apple
   SDK licensing. Not possible across macOS architectures in this setup.

4. **CI coverage** — Android and Windows targets are not yet tested in CI.
   They are build-only, matching the phased rollout approach.
