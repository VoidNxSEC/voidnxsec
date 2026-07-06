{
  description = "VoidNxSEC — NixOS bootstrap cirúrgico + polyglot framework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, nixpkgs, disko, lanzaboote, sops-nix, impermanence, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      imports = [
        ./nix/rust.nix
        ./nix/go.nix
        ./nix/c.nix
        ./nix/cpp.nix
      ];

      perSystem = { config, pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.devShells.rust
            config.devShells.go
            config.devShells.c
            config.devShells.cpp
          ];
          packages = with pkgs; [
            just
            gnumake
            yq
            age
            sops
          ];
        };
      };

      flake = {
        nixosConfigurations = {
          voidnx-server = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              disko.nixosModules.disko
              lanzaboote.nixosModules.lanzaboote
              sops-nix.nixosModules.sops
              impermanence.nixosModules.impermanence
              ./nixos/hosts/server/default.nix
            ];
          };

          voidnx-laptop = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs; };
            modules = [
              disko.nixosModules.disko
              lanzaboote.nixosModules.lanzaboote
              sops-nix.nixosModules.sops
              impermanence.nixosModules.impermanence
              ./nixos/hosts/laptop/default.nix
            ];
          };
        };
      };
    };
}
