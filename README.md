# floresta-nix

Nix packaging, cross-compilation, NixOS service module, and release
infrastructure for [Floresta](https://github.com/getfloresta/Floresta) --
a lightweight Bitcoin full node powered by utreexo.

## What's in the box

| Component          | Path                                                             | Description                                                        |
| ------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| **Flake**          | [`flake.nix`](flake.nix)                                         | Packages, checks, dev shell, and NixOS module exports              |
| **Build library**  | [`lib/floresta-build.nix`](lib/floresta-build.nix)               | Configurable Rust build derivation with cross-compilation support  |
| **Service module** | [`lib/floresta-service.nix`](lib/floresta-service.nix)           | NixOS systemd service with hardened defaults                       |
| **Service tests**  | [`lib/floresta-service-*-test.nix`](lib/)                        | Eval-based and VM integration tests for the service                |
| **Attestation**    | [`contrib/floresta-attest`](contrib/floresta-attest)             | Build binaries and produce GPG-signed hash manifests               |
| **Verification**   | [`contrib/floresta-verify`](contrib/floresta-verify)             | Verify multi-builder consensus on release hashes                   |
| **CI**             | [`ci.yml`](.github/workflows/ci.yml)                             | Build, cross-build, and reproducibility checks                     |
| **Release**        | [`build-and-attest.yml`](.github/workflows/build-and-attest.yml) | Build all targets, attest, and publish GitHub releases             |
| **Recipes**        | [`justfile`](justfile)                                           | Convenience commands for builds, hashing, caching, and attestation |
| **Example**        | [`examples/flake.nix`](examples/flake.nix)                       | Consumer flake showing package and service integration             |
| **Platforms**      | [`PLATFORMS.md`](PLATFORMS.md)                                   | Full build matrix, target notes, and known limitations             |

## Packages

| Package          | Description                                          |
| ---------------- | ---------------------------------------------------- |
| `florestad`      | Full node daemon                                     |
| `floresta-cli`   | CLI client for interacting with `florestad`          |
| `libfloresta`    | Library for embedding Floresta in other applications |
| `floresta-debug` | Debug build with metrics (native only)               |
| `default`        | All of the above                                     |

### Quickstart

```bash
# Run the node
nix run github:getfloresta/floresta-nix

# Build a specific package
nix build github:getfloresta/floresta-nix#floresta-cli

# Cross-compile for another target
nix build .#florestad-aarch64-linux
nix build .#florestad-x86_64-windows
nix build .#florestad-aarch64-android
```

### Supported targets

Native and cross-compiled binaries are available for:

| Target          | Toolchain                     | Packages                                   |
| --------------- | ----------------------------- | ------------------------------------------ |
| x86_64-linux    | native                        | all                                        |
| aarch64-linux   | native                        | all                                        |
| x86_64-darwin   | native                        | all                                        |
| aarch64-darwin  | native                        | all                                        |
| x86_64-windows  | MinGW cross                   | `florestad`, `floresta-cli`                |
| aarch64-android | NDK cross (x86_64 hosts only) | `florestad`, `floresta-cli`, `libfloresta` |
| armv7a-android  | NDK cross (x86_64 hosts only) | `florestad`, `floresta-cli`, `libfloresta` |

See [PLATFORMS.md](PLATFORMS.md) for the full host-to-target build matrix
and known limitations.

### Using in your own flake

```nix
{
  inputs.floresta-nix.url = "github:getfloresta/floresta-nix";

  outputs = { nixpkgs, floresta-nix, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      florestaBuild = import "${floresta-nix}/lib/floresta-build.nix" { inherit pkgs; };
    in {
      packages.x86_64-linux = {
        florestad = florestaBuild.florestad;
        floresta-cli = florestaBuild.floresta-cli;
      };
    };
}
```

See [`examples/flake.nix`](examples/flake.nix) for a multi-platform example
with the NixOS service module.

### Build options

`florestaBuild.mkFloresta` accepts:

| Option             | Type            | Default         | Description                                                                   |
| ------------------ | --------------- | --------------- | ----------------------------------------------------------------------------- |
| `packageName`      | enum            | `"all"`         | `"all"`, `"florestad"`, `"floresta-cli"`, `"libfloresta"`, `"floresta-debug"` |
| `src`              | path            | pinned revision | Override the Floresta source tree                                             |
| `features`         | list of str     | `[]`            | Additional Cargo features to enable                                           |
| `extraBuildInputs` | list of package | `[]`            | Extra build-time dependencies                                                 |
| `doCheck`          | bool            | `true`          | Run tests during build                                                        |

## NixOS Service Module

Exported as `nixosModules.floresta` (and `nixosModules.default`). Provides a
systemd service for running `florestad` with sandboxed defaults.

```nix
{
  imports = [ floresta-nix.nixosModules.floresta ];

  services.floresta = {
    enable = true;
    network = "signet";
    electrum.address = "127.0.0.1:50001";
    rpc.address = "127.0.0.1:38332";
  };
}
```

<details>
<summary>All service options</summary>

| Option                      | Type         | Default             | Description                                        |
| --------------------------- | ------------ | ------------------- | -------------------------------------------------- |
| `enable`                    | bool         | `false`             | Enable the Floresta systemd service                |
| `package`                   | package      | `pkgs.floresta`     | The florestad package to use                       |
| `network`                   | enum         | `"bitcoin"`         | `"bitcoin"`, `"signet"`, or `"regtest"`            |
| `dataDir`                   | path         | `/var/lib/floresta` | Directory for chain and wallet data                |
| `user`                      | str          | `"floresta"`        | User under which floresta runs                     |
| `group`                     | str          | `"floresta"`        | Group under which floresta runs                    |
| `assumeUtreexo`             | bool         | `true`              | Use assume-utreexo for faster initial sync         |
| `assumeValid`               | str          | `"hardcoded"`       | `"hardcoded"`, `"0"` (disabled), or a block hash   |
| `backfill`                  | bool         | `true`              | Backfill blocks skipped during assume-utreexo sync |
| `cfilters`                  | bool         | `true`              | Build compact block filters (BIP 157/158)          |
| `filtersStartHeight`        | int or null  | `null`              | Block height to start downloading filters from     |
| `connect`                   | str or null  | `null`              | Connect only to this specific node                 |
| `proxy`                     | str or null  | `null`              | SOCKS5 proxy (e.g. Tor)                            |
| `debug`                     | bool         | `false`             | Enable verbose debug logging                       |
| `logToFile`                 | bool         | `false`             | Write logs to file in data directory               |
| `allowV1Fallback`           | bool         | `false`             | Allow fallback to v1 P2P transport                 |
| `disableDnsSeeds`           | bool         | `false`             | Disable DNS seed discovery                         |
| `rpc.address`               | str or null  | `null`              | JSON-RPC server address (host:port)                |
| `electrum.address`          | str or null  | `null`              | Electrum server listen address                     |
| `electrum.tls.enable`       | bool         | `false`             | Enable Electrum TLS                                |
| `electrum.tls.address`      | str or null  | `null`              | Electrum TLS listen address                        |
| `electrum.tls.certPath`     | path or null | `null`              | TLS certificate path                               |
| `electrum.tls.keyPath`      | path or null | `null`              | TLS private key path                               |
| `electrum.tls.generateCert` | bool         | `false`             | Auto-generate self-signed certificate              |
| `walletDescriptors`         | list of str  | `[]`                | Output descriptors to watch                        |
| `walletXpubs`               | list of str  | `[]`                | Extended public keys to watch                      |
| `zmqAddress`                | str or null  | `null`              | ZMQ push/pull server address                       |
| `extraArgs`                 | list of str  | `[]`                | Extra CLI arguments passed to florestad            |

</details>

The service includes systemd hardening (sandboxing, restricted syscalls,
private tmp, `ProtectSystem=strict`) out of the box.

## Release Verification

Floresta uses a multi-builder attestation system inspired by Bitcoin Core's
Guix reproducible builds. Multiple independent builders compile the same
tagged source, hash the binaries, and sign the hash manifest with GPG. Users
verify that all trusted signers agree on identical hashes.

### Verifying a release

```bash
# Clone floresta.sigs adjacent to floresta-nix
git clone https://github.com/getfloresta/floresta.sigs

# Verify
./contrib/floresta-verify v0.9.0
```

The script imports trusted keys from `contrib/trusted-keys/`, verifies each
signature, and checks consensus across all signers.

### Becoming a signer

1. Add your GPG public key to `contrib/trusted-keys/yourname.asc` via PR
2. Build and attest the release:

```bash
git checkout v0.9.0
./contrib/floresta-attest v0.9.0 yourname
```

3. Submit your attestation to the
   [floresta.sigs](https://github.com/getfloresta/floresta.sigs) repository:

```bash
cp -r sigs/v0.9.0/yourname ../floresta.sigs/v0.9.0/
cd ../floresta.sigs
git add v0.9.0/yourname && git commit -m "sign: attest v0.9.0 as yourname"
```

## Development

```bash
# Enter the dev shell (provides just, nixfmt, deadnix, nil, statix)
nix develop

# Or with direnv
direnv allow

# Run all checks
just check

# Build everything for your host
just cross-build-all

# Hash all built binaries
just check-hashes

# Push to Cachix
just cachix-push
```

## CI

Builds run on every push and PR across all supported platforms. The CI
pipeline includes:

- Nix flake evaluation and linting
- NixOS service eval and VM integration tests
- Native builds on x86_64-linux, aarch64-linux, and aarch64-darwin
- Cross-compilation builds (Linux-to-Linux, Darwin-to-Linux)
- Reproducibility verification (cross-compiled hash comparison across hosts)
- Cachix binary cache population

Builds are cached on [Cachix](https://app.cachix.org/cache/floresta-flake)
and dependencies are tracked by Dependabot.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE) at
your option.
