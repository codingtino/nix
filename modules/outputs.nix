{ config, inputs, ... }:
let
  hardwareProfiles = inputs.nixos-hardware.nixosModules;
  hardwareProfileNames = builtins.attrNames hardwareProfiles;

  mkNixosConfiguration =
    {
      userName,
      hostName,
      hardwareConfiguration,
      hardwareProfile ? null,
      enableBroadcomSta ? false,
      enableHibernation ? false,
      enableZram ? true,
    }:
    let
      selectedHardwareProfile =
        if hardwareProfile == null then
          [ ]
        else if builtins.hasAttr hardwareProfile hardwareProfiles then
          [ hardwareProfiles.${hardwareProfile} ]
        else
          throw "Unknown nixos-hardware profile: ${hardwareProfile}";
    in
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit
          enableBroadcomSta
          enableHibernation
          enableZram
          hostName
          inputs
          userName
          ;
      };
      modules = [
        config.dendritic.nixos.NIXOS
        inputs.home-manager.nixosModules.home-manager
        hardwareConfiguration
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = { inherit inputs userName; };
            users.${userName} = config.dendritic.home.default;
          };
        }
      ] ++ selectedHardwareProfile;
    };

  mkDarwinConfiguration =
    {
      userName,
      system ? "aarch64-darwin",
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = { inherit inputs userName; };
      modules = [
        config.dendritic.darwin."MACOS-NIX"
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = { inherit inputs userName; };
            users.${userName} = config.dendritic.home.default;
          };
        }
      ];
    };
in
{
  systems = [
    "aarch64-darwin"
    "x86_64-darwin"
    "x86_64-linux"
  ];

  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixfmt-tree;

    devShells.default = pkgs.mkShellNoCC {
      packages = [ pkgs.nixfmt-tree ];
    };
  };

  flake = {
    darwinConfigurations."MACOS-NIX" = mkDarwinConfiguration {
      userName = "tino";
    };

    lib = {
      inherit
        hardwareProfileNames
        mkDarwinConfiguration
        mkNixosConfiguration
        ;
      hardwareProfileNamesText = builtins.concatStringsSep "\n" hardwareProfileNames + "\n";
    };
  };
}
