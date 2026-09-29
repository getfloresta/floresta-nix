# List all available recipes
default:
    @just --list

# Run all nix sanity checks
check:
    nix flake check -L
    nix flake check ./examples -L --no-build

# Build one distro of one release (just build aarch64-darwin 0.9.1)
build distro release:
    #!/usr/bin/env bash
    set -euo pipefail
    release="{{ release }}"
    nix build -L ".#florestad-{{ distro }}-v${release//./_}"

# Build every distro this host produces into artifacts/<release>/, named <file>-<triple>; every release, or only the one given (just build-and-package-all 0.9.1)
build-and-package-all release="":
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
    release="{{ release }}"
    suffix="-v${release//./_}"
    root=".#packages.$SYSTEM"

    found=0
    mismatch=0
    for pkg in $(nix eval --raw "$root" --apply 'ps: toString (builtins.attrNames ps)'); do
        [[ -z "$release" || "$pkg" == *"$suffix" ]] || continue
        echo "Building $pkg for $SYSTEM..."
        out=$(nix build -L --no-link --print-out-paths "$root.$pkg")
        triple=$(nix eval --raw "$root.$pkg.rustTarget")
        # One directory per release: the file names repeat across releases.
        dir="artifacts/$(nix eval --raw "$root.$pkg.release.version")"
        mkdir -p "$dir"
        for f in "$out"/bin/* "$out"/lib/*; do
            [ -f "$f" ] || continue
            artifact="$dir/$(basename "$f")-$triple"
            # An artifact already there is never overwritten: it must be the
            # same bytes, or the build did not reproduce it.
            if [ -e "$artifact" ]; then
                if cmp -s "$f" "$artifact"; then
                    echo "✅ Matches $artifact"
                else
                    echo "❌ $artifact differs from $f" >&2
                    mismatch=$((mismatch + 1))
                fi
                continue
            fi
            # Copied read-only, as the store has it.
            cp -L "$f" "$artifact"
            echo "✅ Packaged $artifact"
        done
        found=$((found + 1))
    done
    [ "$found" -gt 0 ] || { echo "error: $SYSTEM has no package${release:+ of release $release}" >&2; exit 1; }
    [ "$mismatch" -eq 0 ] || { echo "error: $mismatch artifact(s) did not reproduce" >&2; exit 1; }

# The attestation verbs below are flake apps; these are shorthands for them.

# List the releases that can be attested
releases:
    @nix run .#releases

# Build, hash and sign a release manifest into contrib/sigs/ (long build; GPG_KEY picks a key)
attest version signer:
    nix run .#attest -- {{ version }} {{ signer }}

# Check every collected attestation: signatures, then consensus
verify:
    nix run .#verify

# Import the release-signing keys into your own GPG keyring
import-keys:
    gpg --import contrib/trusted-keys/*.asc

# Clean build artifacts
clean:
    rm -rf result artifacts

update:
    nix flake update --flake ./examples/
    nix flake update
