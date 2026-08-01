{ ... }:
{
  dendritic.home.tino = {
    programs.git = {
      enable = true;
      settings = {
        init.defaultBranch = "main";
        pull.rebase = false;
        push.autoSetupRemote = true;
      };
    };
  };
}
