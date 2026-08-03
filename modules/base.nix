{ ... }:
{
  dendritic.nixos.NIXOS =
    {
      enableBroadcomSta,
      hostName,
      lib,
      pkgs,
      userName,
      ...
    }:
    {
      networking.hostName = hostName;
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "26.05";

      boot.loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      # Keep systemd-boot's random seed private on the FAT EFI partition.
      fileSystems."/boot".options = lib.mkAfter [ "umask=0077" ];

      nix = {
        package = pkgs.nix;
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
        };
      };

      nixpkgs.config = {
        allowUnfreePredicate = pkg:
          builtins.elem (lib.getName pkg) (
            [ "terraform" "tailscale" ] ++ lib.optional enableBroadcomSta "broadcom-sta"
          );
        allowInsecurePredicate = pkg:
          enableBroadcomSta && lib.getName pkg == "broadcom-sta";
      };

      programs.zsh.enable = true;
      environment.systemPackages = [ pkgs.bashInteractive pkgs.tailscale ];

      services.tailscale.enable = true;

      users.users.root.hashedPassword = "!";
      system.activationScripts.lockRootPassword = {
        deps = [ "users" ];
        text = ''
          ${pkgs.shadow}/bin/passwd --lock root
        '';
      };

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
      };
    };

  dendritic.darwin."MACOS-NIX" =
    {
      lib,
      pkgs,
      userName,
      ...
    }:
    {
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) [ "terraform" ];

      system = {
        primaryUser = userName;
        stateVersion = 6;
      };

      nix = {
        enable = true;
        package = pkgs.nix;
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
        };
      };

      programs.zsh.enable = true;
      environment = {
        shells = [
          pkgs.zsh
          pkgs.bashInteractive
        ];
        systemPackages = [ pkgs.bashInteractive ];
      };

      users.users.${userName} = {
        home = "/Users/${userName}";
        shell = pkgs.zsh;
      };
    };

  dendritic.home.default =
    {
      pkgs,
      userName,
      ...
    }:
    {
      home = {
        username = userName;
        homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${userName}" else "/home/${userName}";
        stateVersion = "26.05";
      };

      xdg.enable = true;
      programs.home-manager.enable = true;
    };
}
