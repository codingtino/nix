{ ... }:
{
  dendritic.home.tino = {
    programs.helix = {
      enable = true;
      defaultEditor = true;
      settings = {
        theme = "base16_default_dark";
        editor = {
          bufferline = "multiple";
          color-modes = true;
          cursorline = true;
          line-number = "relative";
        };
      };
    };
  };
}
