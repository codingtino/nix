{ ... }:
{
  dendritic.nixos.NIXOS = { lib, ... }: {
    networking = {
      networkmanager.enable = true;
      useDHCP = lib.mkDefault true;
      firewall.enable = true;
    };

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = false;
      };
    };
  };
}
