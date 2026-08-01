{ ... }:
{
  dendritic.home.default = { config, pkgs, ... }: {
    home.packages = [ pkgs.bashInteractive ];

    programs = {
      bash.enable = true;

      zsh = {
        enable = true;
        enableCompletion = true;
        autocd = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        history = {
          path = "${config.xdg.dataHome}/zsh/history";
          size = 10000;
          save = 10000;
          ignoreDups = true;
          share = true;
        };
      };

      eza = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        icons = "auto";
        git = true;
      };

      fzf = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        defaultOptions = [
          "--height=40%"
          "--layout=reverse"
          "--border"
        ];
      };
    };
  };
}
