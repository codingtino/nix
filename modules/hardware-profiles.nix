{ inputs, ... }:
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

  macBookProA1706IsoKeyboard =
    { ... }:
    {
      # Apple SPI reports the German ISO-only key next to left Shift as TLDE
      # unless its ISO correction is enabled, exchanging the physical < and ^ keys.
      boot.extraModprobeConfig = ''
        options applespi iso_layout=1
      '';
    };

  macBookProA1706Wireless =
    {
      enableBroadcomSta,
      pkgs,
      ...
    }:
    let
      bcm43602NvramSource = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/DeyAgrO/macbook-pro-13-2-linux/1d52273baa4d86f71113b4e65a181c839fce94fb/firmware/brcmfmac43602-pcie.txt";
        hash = "sha256-mXstlbXugi2lf3BPd+mF/5lbFRw3BbMu5GVuJcH2xH4=";
      };
      bcm43602Nvram = pkgs.runCommand "brcmfmac43602-apple-nvram" { } ''
        install -Dm644 ${bcm43602NvramSource} "$out/lib/firmware/brcm/brcmfmac43602-pcie.txt"
        substituteInPlace "$out/lib/firmware/brcm/brcmfmac43602-pcie.txt" \
          --replace-fail "macaddr=xx:xx:xx:xx:xx:xx" "macaddr=00:90:4c:0d:f4:3e"
      '';
    in
    {
      # A1706 uses BCM43602 with brcmfmac, not B43 or the proprietary STA driver.
      boot.extraModprobeConfig = ''
        options brcmfmac feature_disable=0x82000 roamoff=1
      '';
      hardware.firmware = [ bcm43602Nvram ];
      networking = {
        enableB43Firmware = false;
        networkmanager.wifi = {
          macAddress = "stable";
          powersave = false;
          scanRandMacAddress = false;
        };
      };
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

  macBookPro142TouchBar =
    { config, pkgs, ... }:
    let
      touchBarModule = pkgs.callPackage ../packages/apple-t1-touchbar.nix {
        kernel = config.boot.kernelPackages.kernel;
      };
    in
    {
      warnings = [
        "Experimental out-of-tree Apple T1 Touch Bar support is enabled for MacBookPro14,2."
      ];
      boot = {
        extraModulePackages = [ touchBarModule ];
        initrd.kernelModules = [
          "apple-ibridge"
          "apple-touchbar"
        ];
        extraModprobeConfig = ''
          options apple_ibridge skip_acpi_power=1
          options apple_touchbar fnmode=1 idle_timeout=-1
        '';
      };
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="8600", ATTR{bConfigurationValue}="1"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="8600", TEST=="power/control", ATTR{power/control}="on"
      '';
    };
in
{
  dendritic.hardwareKeyboardConfigs = {
    apple-macbook-pro-13-2 = {
      layout = "de";
      brightnessDevice = "backlight:acpi_video0";
    };
    apple-macbook-pro-14-2 = {
      model = "macbook78";
      layout = "de";
      variant = "mac";
      brightnessDevice = "backlight:acpi_video0";
    };
    lenovo-thinkpad-l14-gen1 = {
      model = "pc105";
      layout = "de";
    };
  };

  # These profiles extend rather than fork the pinned nixos-hardware collection.
  dendritic.hardwareProfiles = {
    apple-macbook-pro-13-2 = {
      imports = [
        upstreamHardwareProfiles.apple-macbook-pro
        upstreamHardwareProfiles.common-hidpi
        upstreamHardwareProfiles.common-pc-ssd
        macBookProA1706Input
        macBookProA1706IsoKeyboard
        macBookProA1706Wireless
        macBookProA1706NvmeResume
      ];
      services.xserver.xkb.layout = "de";
    };

    apple-macbook-pro-14-2 = {
      imports = [
        # MacBookPro14,1 supplies the shared Kaby Lake, Apple SPI and HiDPI setup.
        upstreamHardwareProfiles.apple-macbook-pro-14-1
        macBookProA1706IsoKeyboard
        macBookProA1706Wireless
        macBookProA1706NvmeResume
        macBookPro142TouchBar
      ];
      services.xserver.xkb = {
        model = "macbook78";
        layout = "de";
        variant = "mac";
      };
    };

    lenovo-thinkpad-l14-gen1 = {
      imports = [
        upstreamHardwareProfiles.lenovo-thinkpad-l14-gen1-intel
        upstreamHardwareProfiles.common-pc-ssd
      ];
      services.xserver.xkb = {
        model = "pc105";
        layout = "de";
      };
    };
  };
}
