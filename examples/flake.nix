# Example consumer flake — shows how to use floresta-nix's build library.
# Used in CI to verify the consumer integration interface.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    floresta-nix.url = "path:../";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      floresta-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        florestaBuild = import "${floresta-nix}/lib/floresta-build.nix" { inherit pkgs; };
      in
      {
        packages = {
          florestad = florestaBuild.build { packageName = "florestad"; };
          floresta-cli = florestaBuild.build { packageName = "floresta-cli"; };
          default = florestaBuild.build { packageName = "all"; };
        };
      }
    );
}
