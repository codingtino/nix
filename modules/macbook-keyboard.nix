# MacBook Pro 14,2 keyboard fix for German layout.
#
# Only applied to apple-macbook-pro-14-2 hardware profile.
# Fixes: @ symbol (was producing ł), ^ and < keys being swapped.
# Uses "macbook" model instead of "pc105" for correct scancode mapping.
# Works with Wayland compositors (DMS/Niri) via the macbookKeyboard arg.
{ lib, ... }:
{
  options.hardware.macbook-keyboard = {
    enable = lib.mkEnableOption "MacBook Pro keyboard fix for German layout";
  };
}
