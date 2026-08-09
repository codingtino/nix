{ ... }:
{
  dendritic.nixos.NIXOS =
    {
      pkgs,
      userName,
      ...
    }:
    {
      users.users.${userName} = {
        isNormalUser = true;
        description = userName;
        shell = pkgs.zsh;
        extraGroups = [
          "input"
          "networkmanager"
          "video"
          "wheel"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9NGlk8rEOSLKF7MsqoeRa/9idlKkPnl/gPNeuTnHe9 MBP"
        ];
      };

      security.sudo.extraRules = [
        {
          users = [ userName ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
}
