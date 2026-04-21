# floresta-nix

Nix packaging for [Floresta](https://github.com/getfloresta/Floresta).

## Packages

This flake exports the following packages:

| Package          | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| `florestad`      | The Floresta full node daemon                                   |
| `floresta-cli`   | Command-line interface for interacting with florestad           |
| `libfloresta`    | The Floresta library                                            |
| `floresta-debug` | florestad and floresta-cli built with debug profile and metrics |
| `default`        | All of the above                                                |

### Supported platforms

| Platform | Architecture                            |
| -------- | --------------------------------------- |
| Linux    | x86_64, aarch64                         |
| macOS    | x86_64 (Intel), aarch64 (Apple Silicon) |

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
      packages.x86_64-linux.florestad = florestaBuild.build {
        packageName = "florestad";
      };
    };
}
```

See [`examples/flake.nix`](examples/flake.nix) for a multi-platform example using `flake-utils`.

### Build options

`florestaBuild.build` accepts:

| Option             | Type            | Default                | Description                                                                   |
| ------------------ | --------------- | ---------------------- | ----------------------------------------------------------------------------- |
| `packageName`      | enum            | `"all"`                | `"all"`, `"florestad"`, `"floresta-cli"`, `"libfloresta"`, `"floresta-debug"` |
| `src`              | path            | Pinned GitHub revision | Override the Floresta source tree                                             |
| `features`         | list of str     | `[]`                   | Additional cargo features to enable                                           |
| `extraBuildInputs` | list of package | `[]`                   | Extra build-time dependencies                                                 |
| `doCheck`          | bool            | `true`                 | Run tests during build                                                        |

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

Floresta uses a multi-builder attestation system to provide cryptographic proof
that multiple independent builders produce identical binaries. This gives users
confidence that the binaries they download match what the source code produces.

### How it works

The system mirrors Bitcoin Core's Guix build verification workflow:

1. **Each builder independently compiles** the release from the same tagged source
   commit, producing binaries for all target platforms.

2. **Each builder hashes** their binaries using SHA256 and records the hashes
   in a `SHA256SUMS` file.

3. **Each builder signs** their `SHA256SUMS` file with their GPG key,
   producing a `SHA256SUMS.asc` detached signature.

4. **All signatures are collected** in the
   [floresta.sigs](https://github.com/getfloresta/floresta.sigs) repository.

5. **Users verify** by checking that all trusted signers agree on the same
   hashes. Any mismatch indicates a problem.

### Verifying a release

Ensure `floresta.sigs` is cloned adjacent to `floresta-nix`, then run:

```bash
cd floresta-nix
./contrib/floresta-verify v0.9.0
```

The script will import trusted GPG keys, verify each signature, and check that
all valid signers report identical hashes.

Example output:

```
Importing trusted keys...
  OK   jaoleal
  OK   contributor2

Checking signatures for v0.9.0...
  OK   jaoleal (key: ABCD1234...)
  OK   contributor2 (key: EF567890...)

Valid signers: 2

Checking consensus...
  OK   florestad-x86_64-linux       abc123... (2/2 agree)
  OK   florestad-aarch64-linux      def456... (2/2 agree)
  OK   floresta-cli-x86_64-linux    789abc... (2/2 agree)
  OK   floresta-cli-aarch64-linux   fed321... (2/2 agree)

All 2 signers agree. Release verified.
```

### Becoming a signer

1. Add your GPG public key to `contrib/trusted-keys/yourname.asc` via PR

2. Clone the release tag and run the attestation script:

```bash
git clone https://github.com/getfloresta/floresta-nix
cd floresta-nix
git checkout v0.9.0
./contrib/floresta-attest v0.9.0 yourname
```

3. Copy the output to your `floresta.sigs` clone and submit a PR:

```bash
cp -r sigs/v0.9.0/yourname ./floresta.sigs/v0.9.0/
cd ../floresta.sigs
git checkout -b attest/v0.9.0/yourname
git add v0.9.0/yourname
git commit -m "sign: attest v0.9.0 as yourname"
gh pr create
```

### Trusted keys

The `contrib/trusted-keys/` directory (imported as a submodule from
`floresta.sigs`) contains GPG public keys for all authorized signers.
A signature is only valid if it comes from a key in this list.

## CI

All packages are built across every supported platform on each push and PR. Builds are cached on [Cachix](https://app.cachix.org/cache/floresta-flake), dependencies are tracked by Dependabot, and a weekly scheduled build catches upstream breakage early.
