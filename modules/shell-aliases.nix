{ ... }:
{
  dendritic.home.default =
    { pkgs, ... }:
    let
      wrapperPath = if pkgs.stdenv.hostPlatform.isDarwin then "/etc/nix-darwin" else "/etc/nixos";
      rebuildCommand = if pkgs.stdenv.hostPlatform.isDarwin then "darwin-rebuild" else "nixos-rebuild";
    in
    {
      home.shellAliases.nrs = "sudo nix flake update --flake ${wrapperPath} nix-config && sudo ${rebuildCommand} switch --flake ${wrapperPath}#system";
    };
}
