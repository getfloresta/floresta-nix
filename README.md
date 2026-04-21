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

## CI

All packages are built across every supported platform on each push and PR. Builds are cached on [Cachix](https://app.cachix.org/cache/floresta-flake), dependencies are tracked by Dependabot, and a weekly scheduled build catches upstream breakage early.
