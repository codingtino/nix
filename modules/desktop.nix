{ ... }:
{
  dendritic.nixos.NIXOS = {
    programs = {
      mangowc.enable = true;

      dms-shell = {
        enable = true;
        systemd = {
          enable = true;
          target = "mango-session.target";
          restartIfChanged = true;
        };
        enableSystemMonitoring = true;
        enableVPN = false;
        enableDynamicTheming = true;
        enableAudioWavelength = false;
        enableCalendarEvents = false;
        enableClipboardPaste = true;
      };
    };

    services.displayManager = {
      defaultSession = "mango";
      sddm = {
        enable = true;
        wayland.enable = true;
      };
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    hardware.bluetooth.enable = true;
    security = {
      polkit.enable = true;
      rtkit.enable = true;
    };

    systemd.user.targets.mango-session = {
      description = "MangoWC graphical session";
      requires = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
    };
  };

  dendritic.home.default = { lib, pkgs, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      xdg.configFile."mango/config.conf".text = ''
        # Environment
        env=QT_QPA_PLATFORM,wayland
        env=ELECTRON_OZONE_PLATFORM_HINT,auto
        env=QT_QPA_PLATFORMTHEME,gtk3
        env=NIXOS_OZONE_WL,1

        # Export the compositor environment and start DMS only for Mango.
        exec-once=dbus-update-activation-environment --systemd --all
        exec-once=systemctl --user start mango-session.target

        # ThinkPad input defaults
        xkb_rules_layout=de
        repeat_rate=40
        repeat_delay=300
        tap_to_click=1
        disable_while_typing=1
        scroll_method=1

        # DMS-friendly appearance
        border_radius=12
        borderpx=0
        focused_opacity=1.0
        unfocused_opacity=0.9
        gappih=5
        gappiv=5
        gappoh=5
        gappov=5
        shadows=1
        shadow_only_floating=1
        shadows_size=10
        shadows_blur=15
        layerrule=noanim:1,layer_name:^dms

        # Core applications and session control
        bind=SUPER,Return,spawn,ghostty
        bind=SUPER,q,killclient
        bind=SUPER+SHIFT,e,quit

        # DankMaterialShell
        bind=SUPER,space,spawn,dms ipc call spotlight toggle
        bind=SUPER,v,spawn,dms ipc call clipboard toggle
        bind=SUPER,m,spawn,dms ipc call processlist focusOrToggle
        bind=SUPER,comma,spawn,dms ipc call settings focusOrToggle
        bind=SUPER,n,spawn,dms ipc call notifications toggle
        bind=SUPER,y,spawn,dms ipc call dankdash wallpaper
        bind=SUPER+ALT,l,spawn,dms ipc call lock lock

        # Laptop media keys
        bind=NONE,XF86AudioRaiseVolume,spawn,dms ipc call audio increment 3
        bind=NONE,XF86AudioLowerVolume,spawn,dms ipc call audio decrement 3
        bind=NONE,XF86AudioMute,spawn,dms ipc call audio mute
        bind=NONE,XF86MonBrightnessUp,spawn,dms ipc call brightness increment 5
        bind=NONE,XF86MonBrightnessDown,spawn,dms ipc call brightness decrement 5

        # DMS windows and Ghostty
        windowrule=isfloating:1,appid:^org\.quickshell$
        windowrule=isnoborder:1,appid:^com\.mitchellh\.ghostty$
      '';
    };
}
