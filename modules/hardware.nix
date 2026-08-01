{ inputs, ... }:
{
  dendritic.nixos.NIXOS = {
    imports = [
      ../hosts/NIXOS/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-l14-intel
    ];

    boot.resumeDevice = "/dev/disk/by-label/swap";

    services.fwupd.enable = true;
  };
}
