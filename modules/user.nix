{ lib, ... }:
{
  dendritic.darwin."MACOS-NIX" =
    { pkgs, userName, ... }:
    {
      users.users.${userName} = {
        home = "/Users/${userName}";
        shell = pkgs.zsh;

        # Add SSH public key for tino
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9NGlk8rEOSLKF7MsqoeRa/9idlKkPnl/gPNeuTnHe9 MBP"
        ];
      };

      # Passwordless sudo for tino
      security.pam.enableSudoLoginToken = true;
      security.rootShell = "/bin/zsh";

      environment.etc."sudoers.d/99-tino".text = ''
        ${userName} ALL=(ALL) NOPASSWD: ALL
      '';
    };

  dendritic.nixos.NIXOS =
    { userName, ... }:
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

        # Add SSH public key for tino
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9NGlk8rEOSLKF7MsqoeRa/9idlKkPnl/gPNeuTnHe9 MBP"
        ];
      };

      # Passwordless sudo for tino
      security.sudo.wheelNoPassword = true;
    };
}
