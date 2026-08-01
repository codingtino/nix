{ ... }:
{
  dendritic.home.default = { pkgs, ... }: {
    programs.ghostty = {
      enable = true;
      package = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.ghostty;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        font-family = "JetBrainsMono Nerd Font";
        font-size = 13;
        cursor-style = "block";
        shell-integration = "detect";
        window-padding-x = 8;
        window-padding-y = 8;
      };
    };
  };
}
