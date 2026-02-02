{
  config,
  src,
  ...
}:
{
  xdg = {
    enable = true;
    configFile = {
      "conda" = {
        recursive = true;
        source = "${src}/conf.d/conda";
      };
      "python" = {
        recursive = true;
        source = "${src}/conf.d/python";
      };
      "glow" = {
        recursive = true;
        source = "${src}/conf.d/glow";
      };
      "npm" = {
        recursive = true;
        source = "${src}/conf.d/npm";
      };
      "tombi" = {
        recursive = true;
        source = "${src}/conf.d/tombi";
      };
      "wget" = {
        recursive = true;
        source = "${src}/conf.d/wget";
      };
      "yarn" = {
        recursive = true;
        source = "${src}/conf.d/yarn";
      };
      # generate a separate file for the lua cpath/path
      # this must be imported by the init.lua file
      "nvim/init.lua".enable = false;
      "nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;

    };
  };
}
