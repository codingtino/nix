{ ... }:
{
  dendritic.home.default = {
    programs.bat = {
      enable = true;
      config = {
        pager = "less -FR";
        style = "numbers,changes,header";
      };
    };
  };
}
