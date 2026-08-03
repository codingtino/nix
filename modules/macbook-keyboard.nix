# MacBook Pro 14,2 keyboard fix for German layout.
#
# Only applied to apple-macbook-pro-14-2 hardware profile.
# Fixes: @ symbol (was producing ł), ^ and < keys being swapped.
# Uses "macbook" model instead of "pc105" for correct scancode mapping.
{ lib, config, ... }:
let
  cfg = config.hardware.macbook-keyboard;
in
{
  options.hardware.macbook-keyboard = {
    enable = lib.mkEnableOption "MacBook Pro keyboard fix for German layout";
  };

  config = lib.mkIf cfg.enable {
    # X server keyboard settings
    services.xserver.xkb = {
      model = "macbook";
      layout = "de";
      variant = "mac";
    };

    # Console keyboard settings
    console.keyMap = "de mac";

    # Home Manager / DMS keyboard settings
    home-manager.sharedModules = [
      {
        config.xdg.configFile."mango/config.conf".text = lib.mkForce ''
          # Environment
          env=QT_QPA_PLATFORM,wayland
          env=ELECTRON_OZONE_PLATFORM_HINT,auto
          env=QT_QPA_PLATFORMTHEME,gtk3
          env=NIXOS_OZONE_WL,1

          # Export the compositor environment and start DMS only for Mango.
          exec-once=dbus-update-activation-environment --systemd --all
          exec-once=systemctl --user start mango-session.target

          # MacBook Pro 14,2 German keyboard settings
          xkb_rules_model=macbook
          xkb_rules_layout=de
          xkb_rules_variant=mac
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
      }
    ];
  };
}
