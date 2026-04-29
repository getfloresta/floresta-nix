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

# Build a cross-compiled package, e.g. `just cross-build florestad-aarch64-linux`
cross-build target:
    nix build -L .#{{ target }}

# Build all cross-compiled targets available on this host
cross-build-all:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    TARGETS=("x86_64-linux" "aarch64-linux" "x86_64-windows")
    PACKAGES=("florestad" "floresta-cli")

    case "${SYSTEM}" in
        x86_64-darwin)  TARGETS+=("x86_64-darwin") ;;
        aarch64-darwin) TARGETS+=("aarch64-darwin") ;;
    esac

    ATTRS=()
    NAMES=()
    for target in "${TARGETS[@]}"; do
        for pkg in "${PACKAGES[@]}"; do
            if [ "${target}" = "${SYSTEM%-*}-${SYSTEM#*-}" ]; then
                ATTR="${pkg}"
            else
                ATTR="${pkg}-${target}"
            fi
            ATTRS+=(".#${ATTR}")
            NAMES+=("${ATTR}")
        done
    done

    echo "Building: ${NAMES[*]}"
    if command -v nom &> /dev/null; then
        nix build -L --no-link "${ATTRS[@]}" --impure 2>&1 | nom
    else
        nix build -L --no-link "${ATTRS[@]}" --impure
    fi

    # Create named result symlinks
    for i in "${!ATTRS[@]}"; do
        nix build "${ATTRS[$i]}" --out-link "result-${NAMES[$i]}" --impure
    done

# Build and package native binaries into artifacts/
build-and-package-all:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    echo "Building release binaries for $SYSTEM..."

    just build florestad
    just _package-binary florestad $SYSTEM

    just build floresta-cli
    just _package-binary floresta-cli $SYSTEM

# Produce a signed attestation for a release
attest version signer:
    ./contrib/floresta-attest {{ version }} {{ signer }}

# Verify attestations for a release
verify version sigs_path="./floresta.sigs":
    ./contrib/floresta-verify {{ version }} {{ sigs_path }}

# Hash all binaries found in result dirs (supports both result-<name> and result-N naming)
check-hashes:
    #!/usr/bin/env bash
    set -euo pipefail
    FOUND=0

    echo "=== Binary hashes ==="

    # Find all result symlinks (result, result-*, result-N)
    for link in result result-*; do
        [ -L "${link}" ] || continue
        [ -d "${link}/bin" ] || continue

        for bin in "${link}"/bin/*; do
            [ -f "${bin}" ] || continue
            HASH=$(shasum -a 256 "${bin}" | cut -d' ' -f1)
            NAME=$(basename "${bin}")
            echo "${HASH}  ${link}/bin/${NAME}"
            FOUND=$((FOUND + 1))
        done
    done

    if [ "${FOUND}" -eq 0 ]; then
        echo "No result directories found. Run 'just cross-build-all' first."
        exit 1
    fi

    echo ""
    echo "${FOUND} binaries hashed"

# Push all result symlinks to Cachix. Falls back to CACHIX_AUTH_TOKEN env var.
cachix-push key="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ key }}" ]; then
        export CACHIX_AUTH_TOKEN="{{ key }}"
    fi
    if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
        echo "Error: no auth token provided. Pass a key argument or set CACHIX_AUTH_TOKEN."
        exit 1
    fi
    PUSHED=0
    for link in result result-*; do
        [ -L "${link}" ] || continue
        echo "Pushing ${link} to floresta-flake..."
        nix run nixpkgs#cachix -- push floresta-flake "${link}"
        PUSHED=$((PUSHED + 1))
    done
    if [ "${PUSHED}" -eq 0 ]; then
        echo "No result directories found. Run 'just build' or 'just cross-build-all' first."
        exit 1
    fi
    echo "${PUSHED} store paths pushed to floresta-flake"

# Build all native packages and push them to Cachix
cachix-build-and-push key="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ key }}" ]; then
        export CACHIX_AUTH_TOKEN="{{ key }}"
    fi
    if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
        echo "Error: no auth token provided. Pass a key argument or set CACHIX_AUTH_TOKEN."
        exit 1
    fi

    echo "Building all packages..."
    SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    PACKAGES=$(nix eval .#packages.${SYSTEM} --apply 'builtins.attrNames' --json | nix run nixpkgs#jq -- -r '.[]')

    for pkg in ${PACKAGES}; do
        echo "Building and pushing ${pkg}..."
        nix build -L ".#${pkg}" --out-link "result-${pkg}"
        nix run nixpkgs#cachix -- push floresta-flake "result-${pkg}"
    done

    echo "All packages built and pushed to floresta-flake"

# Clean build artifacts
clean:
    rm -rf result artifacts

update:
    nix flake update --flake ./examples/
    nix flake update
