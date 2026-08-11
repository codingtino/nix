{ ... }:
{
  dendritic.home.default = { pkgs, ... }: {
    home.packages = [ pkgs.bashInteractive ];
    programs.bash.enable = true;
  };
}
