# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Release attestation independent builders compile the same source, hash the
# artifacts, and sign the manifest into contrib/sigs/; verification confirms
# that every trusted signer reported identical hashes.
#
# The manifest is a derivation; signing and verifying are programs
# (`nix run .#attest`, `nix run .#verify`). `nix flake check` runs the same
# verifier against the committed attestations.
{
  pkgs,
  # The release catalogue, a list of { version, src }. The version names
  # the manifest and its directory under contrib/sigs/.
  releases,
  # Every package this host builds; each carries the release it was built
  # from in passthru.release.
  packages,
  # Directory of trusted release-signing public keys.
  trustedKeys,
  # Collected attestations: <version>/<signer>/SHA256SUMS{,.asc}.
  sigs,
}:

let
  inherit (pkgs) lib;

  # One manifest per release: a "<hash>  <file>-<triple>" line for every
  # file the release's packages install under bin/ and lib/, sorted by
  # artifact name. The triple is the rustTarget each was compiled for.
  manifests = lib.listToAttrs (
    map (
      release:
      lib.nameValuePair release.version (
        pkgs.runCommand "floresta-SHA256SUMS-${release.version}" { } ''
          {
          ${lib.concatMapStrings (drv: ''
            for f in ${drv}/bin/* ${drv}/lib/*; do
                [ -f "$f" ] || continue
                echo "$(sha256sum "$f" | cut -d' ' -f1)  $(basename "$f")-${drv.rustTarget}"
            done
          '') (lib.filter (drv: drv.release.version == release.version) (lib.attrValues packages))}
          } | LC_ALL=C sort -k2 > $out
        ''
      )
    ) releases
  );

  attestableVersions = map (release: release.version) releases;

  # The verifier's logic lives in rust/verify.rs; this compiles it with the
  # flake's gpg and contrib/ copies baked in as the fallback paths.
  verify = pkgs.writers.writeRustBin "floresta-verify" { rustcArgs = [ "--edition=2021" ]; } (
    builtins.replaceStrings
      [ "@gnupg@" "@sigs@" "@trustedKeys@" ]
      [ "${pkgs.gnupg}" "${sigs}" "${trustedKeys}" ]
      (builtins.readFile ./rust/verify.rs)
  );

  # The signer's logic lives in rust/attest.rs; this compiles it with the
  # flake's gpg, the attestable versions and the host's system baked in.
  attest = pkgs.writers.writeRustBin "floresta-attest" { rustcArgs = [ "--edition=2021" ]; } (
    builtins.replaceStrings
      [ "@gnupg@" "@versions@" "@system@" ]
      [
        "${pkgs.gnupg}"
        (lib.concatStringsSep " " attestableVersions)
        pkgs.stdenv.hostPlatform.system
      ]
      (builtins.readFile ./rust/attest.rs)
  );

  # Lists the attestable versions, for `nix run .#releases`.
  listReleases = pkgs.writeShellApplication {
    name = "floresta-releases";
    text = ''
      ${lib.concatMapStrings (v: "echo ${v}\n") attestableVersions}
    '';
  };

  # Runs against the committed copies the flake pins, not the working tree.
  check =
    pkgs.runCommand "floresta-attestations"
      {
        nativeBuildInputs = [ verify ];
      }
      ''
        set -o pipefail
        floresta-verify | tee "$out"
      '';
in
{
  inherit
    manifests
    verify
    attest
    listReleases
    check
    ;
}
