{ ... }:
{
  dendritic.darwin."MACOS-NIX" = {
    system.defaults = {
      dock = {
        autohide = true;
        show-recents = false;
      };

      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
      };
    };
  };
}
