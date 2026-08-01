{ inputs, ... }:
{
  dendritic.nixos.NIXOS = {
    imports = [
      ../hosts/NIXOS/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-l14-intel
    ];

    services.fwupd.enable = true;
  };
}
