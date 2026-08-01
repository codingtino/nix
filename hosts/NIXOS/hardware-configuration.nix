# This tracked guard file MUST be replaced with the file generated on the T480:
#   sudo cp /etc/nixos/hardware-configuration.nix ./hosts/NIXOS/hardware-configuration.nix
# See README.md before building the NIXOS host.
{ ... }:
{
  assertions = [
    {
      assertion = false;
      message = "Replace hosts/NIXOS/hardware-configuration.nix with the T480-generated file before building NIXOS.";
    }
  ];
}
