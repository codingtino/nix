{ ... }:
{
  dendritic.nixos.NIXOS = {
    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "de_DE.UTF-8";
    console.keyMap = "de";
    services.xserver.xkb.layout = "de";
  };
}
