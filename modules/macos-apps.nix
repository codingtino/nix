{ ... }:
{
  dendritic.darwin."MACOS-NIX" = {
    nix-homebrew = {
      enable = true;
      user = "tino";
      enableRosetta = false;
      autoMigrate = true;
      mutableTaps = true;
    };

    homebrew = {
      enable = true;
      brews = [ "macmon" ];
      casks = [
        "ghostty"
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
