{
  description = "A multi-language monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      
      # Modularization Pattern: 
      # We split the flake into separate modules per language/service.
      imports = [
        ./nix/rust.nix
        ./nix/go.nix
        ./nix/c.nix
        ./nix/cpp.nix
      ];

      perSystem = { config, pkgs, ... }: {
        # The default devShell merges all the environment requirements 
        # from our modularized language shells.
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.devShells.rust
            config.devShells.go
            config.devShells.c
            config.devShells.cpp
          ];
          
          # General workspace tools
          packages = with pkgs; [
            just
            gnumake
            yq # Useful for parsing your project.yaml
          ];
        };
      };
    };
}
