# List all available recipes
default:
    @just --list

# Run all nix sanity checks
check:
    nix flake check -L
    nix flake check ./examples -L --no-build

# Build a specific package, receives the package name.
build package="default":
    nix build -L .#{{ package }}

_package-binary package system:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p artifacts
    cp -L result/bin/{{ package }} artifacts/{{ package }}-{{ system }}
    chmod +x artifacts/{{ package }}-{{ system }}
    echo "✅ Packaged {{ package }}-{{ system }}"

# Build and package the binaries.
build-and-package-all:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    echo "Building release binaries for $SYSTEM..."

    just build florestad
    just _package-binary florestad $SYSTEM

    just build floresta-cli
    just _package-binary floresta-cli $SYSTEM

# Clean build artifacts
clean:
    rm -rf result artifacts

update:
    nix flake update --flake ./examples/
    nix flake update
