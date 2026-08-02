# MacBook Pro keyboard fix for German layout.
#
# Problem: pc105 model + mac variant causes wrong key mappings on MacBook Pro 14,2:
#   @ → ł (should be @)
#   ^ → < (should be ^)
#   < → ^ (should be <)
#
# Solution: Use "macbook" model instead of "pc105" for correct scancode mapping.
#
# Usage: Import this module or add to your hardware profile:
#   services.xserver.xkb.model = "macbook";
#   services.xserver.xkb.layout = "de";
#   services.xserver.xkb.variant = "mac";
#   console.keyMap = "de mac";
{ lib, ... }:
{
  # Apply to all NixOS MacBook Pro configurations
  dendritic.nixos.default = {
    services.xserver.xkb.model = "macbook";
    services.xserver.xkb.layout = "de";
    services.xserver.xkb.variant = "mac";
    console.keyMap = "de mac";
  };
}
