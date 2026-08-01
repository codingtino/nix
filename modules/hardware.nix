{ ... }:
{
  dendritic.nixos.NIXOS =
    {
      config,
      enableBroadcomSta,
      enableHibernation,
      enableZram,
      lib,
      ...
    }:
    lib.mkMerge [
      {
        services = {
          fstrim.enable = true;
          fwupd.enable = true;
        };
        zramSwap.enable = enableZram;
      }

      (lib.mkIf enableHibernation {
        boot.resumeDevice = "/dev/disk/by-label/swap";
      })

      (lib.mkIf enableBroadcomSta {
        boot = {
          blacklistedKernelModules = [
            "b43"
            "bcma"
            "brcmfmac"
            "brcmsmac"
          ];
          extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
          kernelModules = [ "wl" ];
        };
      })
    ];
}
