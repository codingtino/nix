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
  };
}
