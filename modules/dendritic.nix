{ lib, ... }:
let
  mkModuleCollection =
    description:
    lib.mkOption {
      inherit description;
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
    };
in
{
  options.dendritic = {
    nixos = mkModuleCollection "Feature modules merged into named NixOS hosts";
    darwin = mkModuleCollection "Feature modules merged into named nix-darwin hosts";
    home = mkModuleCollection "Feature modules merged into named Home Manager users";
    hardwareProfiles = mkModuleCollection "Repository-owned NixOS hardware profiles merged over nixos-hardware";
    hardwareKeyboardConfigs = lib.mkOption {
      description = "Keyboard metadata for repository-owned hardware profiles";
      type = lib.types.lazyAttrsOf (
        lib.types.submodule {
          options = {
            model = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            layout = lib.mkOption {
              type = lib.types.str;
              default = "us";
            };
            variant = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            options = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          };
        }
      );
      default = { };
    };
  };
}
