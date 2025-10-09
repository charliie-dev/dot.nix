{
  xdg = {
    enable = true;
    configFile = {
      # core-utils
      "git" = {
        recursive = true;
        source = ../conf.d/git;
      };
      "conda" = {
        recursive = true;
        source = ../conf.d/conda;
      };
      "python" = {
        recursive = true;
        source = ../conf.d/python;
      };
      "glow" = {
        recursive = true;
        source = ../conf.d/glow;
      };
      "npm" = {
        recursive = true;
        source = ../conf.d/npm;
      };
      "wget" = {
        recursive = true;
        source = ../conf.d/wget;
      };
      "yarn" = {
        recursive = true;
        source = ../conf.d/yarn;
      };
    };
  };
}
