{ src, ... }:
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
      "wget" = {
        recursive = true;
        source = "${src}/conf.d/wget";
      };
      "yarn" = {
        recursive = true;
        source = "${src}/conf.d/yarn";
      };
    };
  };
}
