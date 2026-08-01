{ ... }:
{
  dendritic.nixos.NIXOS = { lib, pkgs, ... }: {
    networking.hostName = "NIXOS";
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";

    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    nix = {
      package = pkgs.nix;
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
      };
    };

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "terraform" ];

    programs.zsh.enable = true;
    environment.systemPackages = [ pkgs.bashInteractive ];

    users.users.root.hashedPassword = "!";
    system.activationScripts.lockRootPassword = {
      deps = [ "users" ];
      text = ''
        ${pkgs.shadow}/bin/passwd --lock root
      '';
    };

    users.users.tino = {
      isNormalUser = true;
      description = "Tino";
      shell = pkgs.zsh;
      extraGroups = [
        "input"
        "networkmanager"
        "video"
        "wheel"
      ];
    };
  };

  dendritic.darwin."MACOS-NIX" = { lib, pkgs, ... }: {
    networking = {
      hostName = "MACOS-NIX";
      localHostName = "MACOS-NIX";
      computerName = "MACOS-NIX";
    };

    nixpkgs.hostPlatform = "aarch64-darwin";
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "terraform" ];

    system = {
      primaryUser = "tino";
      stateVersion = 6;
    };

    nix = {
      enable = true;
      package = pkgs.nix;
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
      };
    };

    programs.zsh.enable = true;
    environment = {
      shells = [ pkgs.zsh pkgs.bashInteractive ];
      systemPackages = [ pkgs.bashInteractive ];
    };

    users.users.tino = {
      home = "/Users/tino";
      shell = pkgs.zsh;
    };
  };

  dendritic.home.tino = { pkgs, ... }: {
    home = {
      username = "tino";
      homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/tino" else "/home/tino";
      stateVersion = "26.05";
    };

    xdg.enable = true;
    programs.home-manager.enable = true;
  };
}
