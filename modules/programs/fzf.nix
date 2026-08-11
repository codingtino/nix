{ ... }:
{
  dendritic.home.default = {
    programs.fzf = {
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
}
