{ lib, config, ... }:
{
  options.dendritic.nixos.hardware.keyboard = {
    model = lib.mkOption {
      type = lib.types.nullable lib.types.str;
      default = null;
      description = "XKB keyboard model (e.g. 'macbook78', 'pc105')";
    };
    layout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "XKB keyboard layout (e.g. 'de', 'us')";
    };
    variant = lib.mkOption {
      type = lib.types.nullable lib.types.str;
      default = null;
      description = "XKB keyboard variant (e.g. 'mac', 'de')";
    };
  };

  config = let
    kb = config.dendritic.nixos.hardware.keyboard;
    hasModel = kb.model != null;
    hasVariant = kb.variant != null;
  in lib.mkIf hasModel {
    services.xserver.xkb = {
      model = kb.model;
      layout = kb.layout;
      variant = lib.mkIf hasVariant kb.variant;
    };
  };
}
