{ lib, ... }:
{
  dendritic.nixos.NIXOS =
    { userName, ... }:
    lib.mkMerge [
      {
        users.users.${userName} = {
          # Add SSH public key for tino
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9NGlk8rEOSLKF7MsqoeRa/9idlKkPnl/gPNeuTnHe9 MBP"
          ];
        };
      }

      {
        # Passwordless sudo for tino
        security.sudo.extraConfig = ''
          ${userName} ALL=(ALL) NOPASSWD: ALL
        '';
      }
    ];
}
