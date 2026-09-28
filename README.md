# floresta-nix

Nix packaging for [Floresta](https://github.com/getfloresta/Floresta).

## Packages

Every package is `florestad` and `floresta-cli` built for one _distro_ — one place they run.
Each host exposes only the distros it knows how to build, and each distro
only exists from the release it first built from.

| Distro            | Runs on             | Built from     | Since  |
| ----------------- | ------------------- | -------------- | ------ |
| `x86_64-linux`    | Linux x86_64        | x86_64-linux   | any    |
| `aarch64-linux`   | Linux aarch64       | aarch64-linux  | any    |
| `aarch64-darwin`  | macOS Apple Silicon | aarch64-darwin | any    |
| `aarch64-android` | Android arm64-v8a   | x86_64-linux   | 0.10.0 |

A distro is dynamically linked unless its name ends in `-static`. Only
static binaries run outside Nix or NixOS: a dynamic one loads its
interpreter and libraries from `/nix/store`.

`packages` holds every release of every distro the host builds, named
`florestad-<distro>-v<release>` with the release's dots as underscores:

```sh
nix build .#florestad-aarch64-darwin-v0_9_1
./result/bin/florestad
nix build .#florestad-aarch64-android-v0_10_0
nix flake show                    # which host builds which package
```

Every package is written out, per host, in
[`lib/targets.nix`](lib/targets.nix); see [PLATFORMS.md](PLATFORMS.md) for
Android.

To build `libfloresta`, or a different set, use the
build library's `mkFloresta` directly — see below.

### Using in your own flake

Add this flake as an input and import the build library:

```nix
{
  inputs.floresta-nix.url = "github:getfloresta/floresta-nix";

  outputs = { nixpkgs, floresta-nix, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      florestaBuild = import "${floresta-nix}/lib/floresta-build.nix" { inherit pkgs; };
    in {
      packages.x86_64-linux.florestad = florestaBuild.mkFloresta {
        packageSet = [ "florestad" ];
      };
    };
}
```

See [`examples/flake.nix`](examples/flake.nix) for a multi-platform example using `flake-utils`.

### Build options

`florestaBuild.mkFloresta` accepts:

| Option             | Type                 | Default                          | Description                                                          |
| ------------------ | -------------------- | -------------------------------- | -------------------------------------------------------------------- |
| `packageSet`       | list of enum         | `[ "florestad" "floresta-cli" ]` | What to build, from `"florestad"`, `"floresta-cli"`, `"libfloresta"` |
| `profile`          | enum                 | `"release"`                      | `"release"` or `"debug"` cargo profile                               |
| `src`              | path                 | Latest release tag               | Override the Floresta source tree                                    |
| `features`         | list of str          | `[]`                             | Additional cargo features to enable                                  |
| `extraBuildInputs` | list of package      | `[]`                             | Extra build-time dependencies                                        |
| `extraEnvVars`     | attrs of str/package | `{}`                             | Environment variables set on the build                               |
| `buildPhase`       | lines or null        | `null`                           | Replaces the cargo build hook (e.g. Android, cargo with `--target`)  |
| `installPhase`     | lines or null        | `null`                           | Replaces the cargo install hook                                      |
| `doCheck`          | bool                 | `false`                          | Run tests during build                                               |

The library also exports `default` (`mkFloresta { }` — florestad and
floresta-cli at the release profile) and `debug` (the same at the debug
profile). The whole `packageSet` builds in one cargo invocation, so its
shared dependency graph compiles once.

## NixOS Service Module

This flake exports a NixOS module at `nixosModules.floresta` (also `nixosModules.default`) that provides a systemd service for running florestad.

See [`examples/flake.nix`](examples/flake.nix) for usage alongside the build library.

### Service options

| Option                      | Type         | Default             | Description                                        |
| --------------------------- | ------------ | ------------------- | -------------------------------------------------- |
| `enable`                    | bool         | `false`             | Enable the Floresta systemd service                |
| `allowV1Fallback`           | bool         | `false`             | Allow fallback to v1 P2P transport                 |
| `assumeUtreexo`             | bool         | `true`              | Use assume-utreexo for faster initial sync         |
| `assumeValid`               | str          | `"hardcoded"`       | `"hardcoded"`, `"0"` (disabled), or a block hash   |
| `backfill`                  | bool         | `true`              | Backfill blocks skipped during assume-utreexo sync |
| `cfilters`                  | bool         | `true`              | Build compact block filters (BIP 157/158)          |
| `connect`                   | str or null  | `null`              | Connect only to this specific node                 |
| `dataDir`                   | path         | `/var/lib/floresta` | Directory for chain and wallet data                |
| `debug`                     | bool         | `false`             | Enable verbose debug logging                       |
| `disableDnsSeeds`           | bool         | `false`             | Disable DNS seed discovery                         |
| `electrum.address`          | str or null  | `null`              | Electrum server listen address                     |
| `electrum.tls.enable`       | bool         | `false`             | Enable Electrum TLS                                |
| `electrum.tls.address`      | str or null  | `null`              | Electrum TLS listen address                        |
| `electrum.tls.certPath`     | path or null | `null`              | TLS certificate path                               |
| `electrum.tls.keyPath`      | path or null | `null`              | TLS private key path                               |
| `electrum.tls.generateCert` | bool         | `false`             | Auto-generate self-signed certificate              |
| `extraArgs`                 | list of str  | `[]`                | Extra CLI arguments passed to florestad            |
| `filtersStartHeight`        | int or null  | `null`              | Block height to start downloading filters from     |
| `group`                     | str          | `"floresta"`        | Group under which floresta runs                    |
| `logToFile`                 | bool         | `false`             | Write logs to file in data directory               |
| `network`                   | enum         | `"bitcoin"`         | `"bitcoin"`, `"signet"`, or `"regtest"`            |
| `package`                   | package      | `pkgs.floresta`     | The florestad package to use                       |
| `proxy`                     | str or null  | `null`              | SOCKS5 proxy (e.g. Tor)                            |
| `rpc.address`               | str or null  | `null`              | JSON-RPC server address (host:port)                |
| `user`                      | str          | `"floresta"`        | User under which floresta runs                     |
| `walletDescriptors`         | list of str  | `[]`                | Output descriptors to watch                        |
| `walletXpubs`               | list of str  | `[]`                | Extended public keys to watch                      |
| `zmqAddress`                | str or null  | `null`              | ZMQ push/pull server address                       |

The service includes systemd hardening (sandboxing, restricted syscalls, private tmp, etc.) out of the box.

## Release Verification

Releases are attested by independent builders. Each builder compiles the same source, hashes the resulting artifacts, and signs the hash manifest with their GPG key. The signed manifests live in [`contrib/sigs/`](contrib/sigs); anyone can then check that every trusted signer reported identical hashes.

Release artifacts are named `<file>-<target triple>` — `florestad-x86_64-unknown-linux-musl`, `florestad-aarch64-apple-darwin`, and so on — the same names used in the manifests, so a downloaded binary can be checked directly against them.

An attestation covers one release and hashes exactly what its distros install on the signer's host. `nix run .#releases` lists the versions.

[`lib/attestation.nix`](lib/attestation.nix) holds the whole mechanism:

|                                                                         |                                                                                                                            |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `nix run .#releases`                                                    | Lists the releases that can be attested                                                                                    |
| `nix run .#attest -- <version> <signer>`                                | Builds the manifest and signs it with your key into `contrib/sigs/<version>/`                                              |
| `nix run .#verify`                                                      | Verifies every collected signature, then the consensus between signers                                                     |
| `nix build '.#legacyPackages.<host>.attestation-manifests."<version>"'` | Just the manifest: builds every distro of that release for your host, hashes the artifacts, writes the sorted `SHA256SUMS` |

The `<version>` is one string throughout: it picks the source tree, names the manifest, and names the directory the signature is filed under. `attest` rejects a version this flake does not pin.

### Verifying a release

```bash
nix run .#verify     # or: just verify
```

`nix flake check` runs the same verifier against what is committed, so CI checks every attestation on every push. It fails if any signature is bad, if any signature comes from a key outside [`contrib/trusted-keys/`](contrib/trusted-keys), or if two signers report different hashes for the same artifact.

Artifacts marked `PARTIAL` are not a failure: they are covered by some signers and not others, because each signer hashes the artifacts their own host builds — a macOS signer cannot attest the Linux binaries, nor the other way around (see [PLATFORMS.md](PLATFORMS.md)).

You do not have to sign anything to check a release: `nix build '.#legacyPackages.<host>.attestation-manifests."<version>"'` produces the manifest on its own, so you can confirm you reproduce the same hashes.

### Becoming a signer

1. Export your public key with:

```bash
gpg --armor --export <KEYID> > contrib/trusted-keys/<yourname>.asc
```

2. Build and sign the release:

```bash
nix run .#attest -- 0.9.1 yourname
```

This writes `contrib/sigs/0.9.1/yourname/SHA256SUMS` and `SHA256SUMS.asc`. Expect a long build: every target is compiled from source. Set `GPG_KEY` if your keyring holds more than one secret key.

3. Check what you just wrote with `nix run .#verify` — it reads your working tree, so it sees the signature before you commit it.
4. Commit both files and open a PR.

Releases published by CI also carry [GitHub build provenance](https://docs.github.com/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds), verifiable with `gh attestation verify <file> --repo getfloresta/floresta-nix`.

## CI

Every package of every host — each release of each distro [`lib/targets.nix`](lib/targets.nix) lists — is built on each push and PR. Builds are cached on [Cachix](https://app.cachix.org/cache/floresta-flake), dependencies are tracked by Dependabot, and a weekly scheduled build catches upstream breakage early.
