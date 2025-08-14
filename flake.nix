{
  description = "Nix-ified alternative to ChromeOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # `nix run github:j-pap/nixelOS`
      apps = forEachSystem (system: {
        default = self.apps.${system}.install;
        install = {
          type = "app";
          program = nixpkgs.lib.getExe self.packages.${system}.install;
          meta.description = "nixelOS installation script";
        };
      });

      nixosConfigurations.nixel = nixpkgs.lib.nixosSystem {
        modules = [
          ./host/configuration.nix
          inputs.disko.nixosModules.disko
          inputs.nix-flatpak.nixosModules.nix-flatpak
        ];
        specialArgs = { inherit inputs; };
      };

      packages = forEachSystem (system: {
        default = self.packages.${system}.install;
        install = nixpkgs.legacyPackages.${system}.callPackage ./install { };
      });
    };
}
