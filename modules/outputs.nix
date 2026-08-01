{ config, inputs, ... }:
{
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];

  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixfmt-tree;

    devShells.default = pkgs.mkShellNoCC {
      packages = [ pkgs.nixfmt-tree ];
    };
  };

  flake = {
    nixosConfigurations.NIXOS = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        config.dendritic.nixos.NIXOS
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = { inherit inputs; };
            users.tino = config.dendritic.home.tino;
          };
        }
      ];
    };

    darwinConfigurations."MACOS-NIX" = inputs.nix-darwin.lib.darwinSystem {
      specialArgs = { inherit inputs; };
      modules = [
        config.dendritic.darwin."MACOS-NIX"
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = { inherit inputs; };
            users.tino = config.dendritic.home.tino;
          };
        }
      ];
    };
  };
}
