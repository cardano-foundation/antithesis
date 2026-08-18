{
  description = "Cardano node test assets for Antithesis platform";
  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
    asciinema.url = "github:paolino/dev-assets?dir=asciinema";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, mkdocs, asciinema, ... }:
    let
      version = self.dirtyShortRev or self.shortRev;
      parts = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [ "x86_64-linux" "aarch64-darwin" ];
        perSystem = { system, pkgs, ... }:
          let
            mkdocs-pkgs = mkdocs.packages.${system};
            asciinema-pkgs = asciinema.packages.${system};
          in {
            devShells.default = pkgs.mkShell {
              buildInputs = [
                pkgs.just
                pkgs.nixfmt-classic
                pkgs.shellcheck
                # Pinned by flake.lock, so `just check-workflows` validates
                # with the same validator locally and in required CI.
                pkgs.actionlint
                pkgs.mkdocs
                mkdocs-pkgs.mkdocs-packages
                mkdocs-pkgs.mkdocs-asciinema-player
                mkdocs-pkgs.mkdocs-markdown-callouts
                asciinema-pkgs.compress
                asciinema-pkgs.resize
                pkgs.asciinema
              ];
              shellHook = ''
                echo "Welcome to the Cardano node test assets development shell!"
                echo "Version: ${version}"
              '';
            };
          };
      };
    in {
      inherit (parts) devShells;
      inherit version;
    };
}
