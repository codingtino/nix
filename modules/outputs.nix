{ config, inputs, ... }:
let
  upstreamHardwareProfiles = inputs.nixos-hardware.nixosModules;

  macBookProA1706Input =
    { lib, ... }:
    {
      # The built-in keyboard must be available before an encrypted root is unlocked.
      boot = {
        initrd.kernelModules = [
          "applespi"
          "spi_pxa2xx_platform"
          "intel_lpss_pci"
          "applesmc"
        ];
        kernelParams = [ "intel_iommu=on" ];
      };

      services.libinput.enable = true;
      environment.etc."libinput/local-overrides.quirks".text = ''
        [MacBook(Pro) SPI Touchpads]
        MatchName=*Apple SPI Touchpad*
        ModelAppleTouchpad=1
        AttrTouchSizeRange=200:150
        AttrPalmSizeThreshold=1100

        [MacBook(Pro) SPI Keyboards]
        MatchName=*Apple SPI Keyboard*
        AttrKeyboardIntegration=internal

        [MacBookPro Touchbar]
        MatchBus=usb
        MatchVendor=0x05AC
        MatchProduct=0x8600
        AttrKeyboardIntegration=internal
      '';

      hardware = {
        enableRedistributableFirmware = lib.mkDefault true;
        cpu.intel.updateMicrocode = lib.mkDefault true;
      };
    };

  macBookProA1706Wireless =
    { enableBroadcomSta, ... }:
    {
      # A1706 uses BCM43602 with brcmfmac, not B43 or the proprietary STA driver.
      networking.enableB43Firmware = false;
      assertions = [
        {
          assertion = !enableBroadcomSta;
          message = "MacBookPro13,2/14,2 must use brcmfmac; broadcom_sta is incompatible";
        }
      ];
    };

  macBookProA1706NvmeResume =
    { ... }:
    {
      # Apple's NVMe controller does not resume from D3cold on these models.
      systemd.services.disable-apple-nvme-d3cold = {
        description = "Disable unsupported D3cold for the Apple NVMe controller";
        wantedBy = [
          "multi-user.target"
          "suspend.target"
        ];
        before = [ "suspend.target" ];
        unitConfig.ConditionPathExists = "/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed";
        serviceConfig.Type = "oneshot";
        script = ''
          device=/sys/bus/pci/devices/0000:01:00.0
          if ! [ "$device/driver" -ef /sys/bus/pci/drivers/nvme ]; then
            echo "Refusing to change D3cold for a non-NVMe device at $device" >&2
            exit 1
          fi
          echo 0 > "$device/d3cold_allowed"
        '';
      };
    };

  localHardwareProfiles = {
    apple-macbook-pro-13-2 = {
      imports = [
        upstreamHardwareProfiles.apple-macbook-pro
        upstreamHardwareProfiles.common-hidpi
        upstreamHardwareProfiles.common-pc-ssd
        macBookProA1706Input
        macBookProA1706Wireless
        macBookProA1706NvmeResume
      ];
    };

    apple-macbook-pro-14-2 = {
      imports = [
        # MacBookPro14,1 supplies the shared Kaby Lake, Apple SPI and HiDPI setup.
        upstreamHardwareProfiles.apple-macbook-pro-14-1
        macBookProA1706Wireless
        macBookProA1706NvmeResume
        # MacBook keyboard fix for German layout (@ symbol, ^/< keys)
        ./macbook-keyboard.nix
      ];
      hardware.macbook-keyboard.enable = true;
    };
  };

  hardwareProfiles = upstreamHardwareProfiles // localHardwareProfiles;
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
          throw "Unknown hardware profile: ${hardwareProfile}";
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
            extraSpecialArgs = {
              inherit inputs userName;
              macbookKeyboard = config.hardware.macbook-keyboard.enable;
            };
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

    nixosConfigurations.system = mkNixosConfiguration {
      userName = "tino";
      hostName = "MBP-NIXOS";
      hardwareConfiguration = inputs.nixos-hardware.nixosModules.apple-macbook-pro-14-2;
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
