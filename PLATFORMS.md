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
| `florestad-x86_64-android`     | x86_64 (emulator)    |
| `floresta-cli-x86_64-android`  | x86_64 (emulator)    |
| `libfloresta-x86_64-android`   | x86_64 (emulator)    |

```bash
nix build .#florestad-aarch64-android
nix build .#libfloresta-armv7a-android
```

---

## Toolchain

`libbitcoinkernel` is built from source for the Android target by
`libbitcoinkernel-sys`'s `build.rs` (via the `cc` crate), using the NDK
clang wrapper that floresta-nix points cargo at. No prebuilt static
library is involved.

- **NDK version:** `27.2.12479018`
- **ANDROID_API_LEVEL:** `24` — this becomes the consumer's effective
  `minSdk` floor. Linking at a lower API level may produce missing-symbol
  errors.
