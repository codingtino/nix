{ ... }:
{
  dendritic.home.default = { config, ... }: {
    programs.zsh = {
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
  };
}
