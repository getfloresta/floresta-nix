# Android Platform Support

## Floresta Android binaries

floresta-nix cross-compiles Floresta for Android using the NDK prebuilt
toolchain. Available on **x86_64-linux** and **x86_64-darwin** only
(nixpkgs' androidndk-pkgs does not map aarch64 build hosts yet).

| Package                        | Target               |
| ------------------------------ | -------------------- |
| `florestad-aarch64-android`    | aarch64 (arm64-v8a)  |
| `floresta-cli-aarch64-android` | aarch64 (arm64-v8a)  |
| `libfloresta-aarch64-android`  | aarch64 (arm64-v8a)  |
| `florestad-armv7a-android`     | armv7a (armeabi-v7a) |
| `floresta-cli-armv7a-android`  | armv7a (armeabi-v7a) |
| `libfloresta-armv7a-android`   | armv7a (armeabi-v7a) |

```bash
nix build .#florestad-aarch64-android
nix build .#libfloresta-armv7a-android
```

---

## Prebuilt `libbitcoinkernel.a`

floresta-nix also distributes prebuilt `libbitcoinkernel.a` static libraries
so that consumers can link `libbitcoinkernel-sys` without compiling Bitcoin
Core from source. Available on **all** build hosts.

### Available packages

| Package                    | Contents                                         |
| -------------------------- | ------------------------------------------------ |
| `android-prebuilt`         | All three targets bundled + REV file             |
| `android-prebuilt-aarch64` | `libbitcoinkernel.a` for aarch64-linux-android   |
| `android-prebuilt-armv7`   | `libbitcoinkernel.a` for armv7-linux-androideabi |
| `android-prebuilt-x86_64`  | `libbitcoinkernel.a` for x86_64-linux-android    |

### Bundle layout (`android-prebuilt`)

```
$out/aarch64/libbitcoinkernel.a
$out/armv7/libbitcoinkernel.a
$out/x86_64/libbitcoinkernel.a
$out/REV
```

```bash
nix build .#android-prebuilt
# or
just android-prebuilt
```

### Nix consumers

Reference any of the prebuilt packages from the floresta-nix flake and
write the cargo override TOML manually (see below) to point
`libbitcoinkernel-sys` at the prebuilt `.a` files.

### Non-Nix consumers

Download the per-target `libbitcoinkernel-<target>-<rev>.tar.zst` archives
from the GitHub Release and extract them:

```bash
mkdir -p prebuilt/aarch64 prebuilt/armv7 prebuilt/x86_64
tar --zstd -xf libbitcoinkernel-aarch64-<rev>.tar.zst -C prebuilt/aarch64
tar --zstd -xf libbitcoinkernel-armv7-<rev>.tar.zst   -C prebuilt/armv7
tar --zstd -xf libbitcoinkernel-x86_64-<rev>.tar.zst  -C prebuilt/x86_64
```

Then create the cargo override (see below) and build:

```bash
cargo ndk -t arm64-v8a build --release
```

### Cargo override TOML

Cargo can skip a crate's `build.rs` entirely when a matching override table
is present in `.cargo/config.toml`. The key is the crate's `links` value,
which for `libbitcoinkernel-sys` is `"libbitcoinkernel.a"`.

Create `.cargo/config.toml` at your workspace root with the following
content, replacing `/absolute/path/to/prebuilt` with the actual path to
your extracted libraries:

```toml
[target.aarch64-linux-android."libbitcoinkernel.a"]
rustc-link-search = ["native=/absolute/path/to/prebuilt/aarch64"]
# Link order matters: bitcoinkernel before c++_static before c++abi.
rustc-link-lib = ["static=bitcoinkernel", "static=c++_static", "static=c++abi"]

[target.armv7-linux-androideabi."libbitcoinkernel.a"]
rustc-link-search = ["native=/absolute/path/to/prebuilt/armv7"]
rustc-link-lib = ["static=bitcoinkernel", "static=c++_static", "static=c++abi"]

[target.x86_64-linux-android."libbitcoinkernel.a"]
rustc-link-search = ["native=/absolute/path/to/prebuilt/x86_64"]
rustc-link-lib = ["static=bitcoinkernel", "static=c++_static", "static=c++abi"]
```

With these tables present, cargo skips `build.rs` for the matching Android
targets. Desktop targets (no matching table) continue to build from source
as usual. The paths **must be absolute** -- cargo resolves relative paths
against the crate directory, which is fragile.

### Correctness invariant

A prebuilt `libbitcoinkernel.a` is valid **only** for the exact tuple of
`(rust-bitcoinkernel rev, target triple, NDK version, API level)`. The
bundle includes a `REV` file containing the `rust-bitcoinkernel` git rev it
was built from. The consumer's `libbitcoinkernel-sys` dependency must be
pinned to the same rev -- a mismatch can cause link errors or (worse) silent
ABI incompatibility.

- **NDK version:** `27.2.12479018`
- **ANDROID_API_LEVEL:** `24` -- this becomes the consumer's effective
  `minSdk` floor. Linking at a lower API level may produce missing-symbol
  errors.
