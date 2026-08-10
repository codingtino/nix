{ config, inputs, ... }:
let
  upstreamHardwareProfiles = inputs.nixos-hardware.nixosModules;

  hardwareProfiles = upstreamHardwareProfiles // config.dendritic.hardwareProfiles;
  hardwareProfileNames = builtins.attrNames hardwareProfiles;

  # Extract keyboard config from a hardware profile
  getKeyboardConfig = profileName:
    if profileName == null then
      { model = null; layout = "us"; variant = null; options = null; brightnessDevice = null; }
    else if builtins.hasAttr profileName config.dendritic.hardwareKeyboardConfigs then
      config.dendritic.hardwareKeyboardConfigs.${profileName}
    else if builtins.hasAttr profileName hardwareProfiles then
      let
        kb = hardwareProfiles.${profileName}.services.xserver.xkb;
      in
      {
        model = kb.model or null;
        layout = kb.layout or "us";
        variant = kb.variant or null;
        options = kb.options or null;
        brightnessDevice = null;
      }
    else
      { model = null; layout = "us"; variant = null; options = null; brightnessDevice = null; };

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
          throw "Unknown hardware profile: ${hardwareProfile}";
      keyboardConfig = getKeyboardConfig hardwareProfile;
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
          keyboardConfig
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
            extraSpecialArgs = { inherit inputs userName keyboardConfig; };
            users.${userName} = config.dendritic.home.default;
          };
        }
      ]
      ++ selectedHardwareProfile;
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
            extraSpecialArgs = {
              inherit inputs userName;
              keyboardConfig = { model = null; layout = "us"; variant = null; };
            };
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

    nixosConfigurations.system = mkNixosConfiguration {
      userName = "tino";
      hostName = "MBP-NIXOS";
      hardwareConfiguration = {};
      hardwareProfile = "apple-macbook-pro-14-2";
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
