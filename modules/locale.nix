{ ... }:
{
  dendritic.nixos.NIXOS = {
    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "de_DE.UTF-8";
    console.keyMap = "de mac";
    services.xserver.xkb = {
      layout = "de";
      model = "macbook";
      variant = "mac";
    };
  };
}
