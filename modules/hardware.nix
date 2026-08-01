{ inputs, ... }:
{
  dendritic.nixos.NIXOS = {
    imports = [
      ../hosts/NIXOS/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t480
    ];

    services.fwupd.enable = true;
  };
}
