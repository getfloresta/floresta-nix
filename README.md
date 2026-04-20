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

## CI

All packages are built across every supported platform on each push and PR. Builds are cached on [Cachix](https://app.cachix.org/cache/floresta-flake), dependencies are tracked by Dependabot, and a weekly scheduled build catches upstream breakage early.
