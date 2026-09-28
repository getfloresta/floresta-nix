# Android Platform Support

## Floresta Android binaries

floresta-nix cross-compiles Floresta for Android using the NDK prebuilt
toolchain. Available on **x86_64-linux** only: the prebuilt toolchain is
the linux-x86_64 one, and nixpkgs' androidndk-pkgs does not map aarch64
build hosts at all.

Each ABI is a distro in [`lib/targets.nix`](lib/targets.nix), building
`florestad` and `floresta-cli` from Floresta 0.10.0 on — the first release whose
libbitcoinkernel-sys cross-compiles for Android.

| Distro            | Target               | Listed by a host |
| ----------------- | -------------------- | ---------------- |
| `aarch64-android` | aarch64 (arm64-v8a)  | x86_64-linux     |
| `armv7a-android`  | armv7a (armeabi-v7a) | not yet          |
| `x86_64-android`  | x86_64 (emulator)    | not yet          |

```bash
nix build .#florestad-aarch64-android-v0_10_0
ls result/bin
```

The ABIs not built yet are commented out under `packages.x86_64-linux` in
`lib/targets.nix`; uncommenting one publishes it.

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
