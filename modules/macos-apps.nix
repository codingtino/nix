{ ... }:
{
  dendritic.darwin."MACOS-NIX" =
    {
      lib,
      pkgs,
      userName,
      ...
    }:
    {
      nix-homebrew = {
        enable = true;
        user = userName;
        enableRosetta = false;
        autoMigrate = true;
        mutableTaps = true;
      };

      homebrew = {
        enable = true;
        brews = lib.optional pkgs.stdenv.hostPlatform.isAarch64 "macmon";
        casks = [
          "hiddenbar"
          "hyperkey"
          "leader-key"
          "rectangle"
        ];

        onActivation = {
          autoUpdate = false;
          upgrade = false;
          cleanup = "none";
        };

        global.autoUpdate = false;
      };
    };
}
