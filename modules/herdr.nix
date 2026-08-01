{ ... }:
let
  version = "0.7.5";

  sources = {
    "aarch64-darwin" = {
      suffix = "macos-aarch64";
      hash = "sha256-NzUFRrABJVWUO5Lq+WJmXeTiZDlbrrRCJ7gBXo/1sNY=";
    };
    "x86_64-linux" = {
      suffix = "linux-x86_64";
      hash = "sha256-PcgyiAc+TC08Z5ow576XvMqRQcb9F9u7khkULpXFklM=";
    };
  };

  mkHerdr = pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
      source = sources.${system} or (throw "Herdr is not packaged for ${system}");
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "herdr";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-${source.suffix}";
        inherit (source) hash;
      };

      dontUnpack = true;

      installPhase = ''
        runHook preInstall
        install -Dm755 "$src" "$out/bin/herdr"
        runHook postInstall
      '';

      meta = {
        description = "Agent multiplexer that lives in your terminal";
        homepage = "https://herdr.dev";
        mainProgram = "herdr";
        platforms = builtins.attrNames sources;
      };
    };
in
{
  perSystem = { pkgs, ... }: {
    packages.herdr = mkHerdr pkgs;
  };

  dendritic.home.tino = { pkgs, ... }: {
    home.packages = [ (mkHerdr pkgs) ];

    xdg.configFile."herdr/config.toml".text = ''
      # Herdr works with its built-in defaults.
      # Add personal settings here when migrating the existing configuration.
    '';
  };
}
