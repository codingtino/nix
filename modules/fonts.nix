{ ... }:
{
  dendritic.nixos.NIXOS = { pkgs, ... }: {
    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
  };

  dendritic.darwin."MACOS-NIX" = { pkgs, ... }: {
    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
  };

  dendritic.home.default = { pkgs, ... }: {
    fonts.fontconfig.enable = pkgs.stdenv.hostPlatform.isLinux;
  };
}
