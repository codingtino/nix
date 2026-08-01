{ ... }:
{
  dendritic.home.default = { pkgs, ... }: {
    home.packages = with pkgs; [
      curl
      rsync
      terraform
      tree
      wget
    ];

    programs = {
      bat = {
        enable = true;
        config = {
          pager = "less -FR";
          style = "numbers,changes,header";
        };
      };

      btop = {
        enable = true;
        settings = {
          color_theme = "Default";
          update_ms = 1000;
          vim_keys = true;
        };
      };
    };
  };
}
