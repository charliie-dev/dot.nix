{
  config,
  pkgs,
  lib,
  src,
  ...
}:
{
  xdg = {
    enable = true;
    configFile = {
      # aube pkg-manager exemptions (allowlist + trust exclude) for the mise npm
      # backend — see conf.d/aube/config.toml and modules/apps/mise.nix. Single
      # file (not recursive) so HM doesn't claim the whole ~/.config/aube dir.
      "aube/config.toml".source = "${src}/conf.d/aube/config.toml";
      "carapace/specs" = {
        recursive = true;
        source = "${src}/conf.d/carapace/specs";
      };
      "conda" = {
        recursive = true;
        source = "${src}/conf.d/conda";
      };
      "python" = {
        recursive = true;
        source = "${src}/conf.d/python";
      };
      "ghostty" = {
        recursive = true;
        source = "${src}/conf.d/ghostty";
      };
      "glow" = {
        recursive = true;
        source = "${src}/conf.d/glow";
      };
      "hunk" = {
        recursive = true;
        source = "${src}/conf.d/hunk";
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
      # "yarn" = {
      #   recursive = true;
      #   source = "${src}/conf.d/yarn";
      # };
      # generate a separate file for the lua cpath/path
      # this must be imported by the init.lua file
      "nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;
    }
    # Docker CLI plugins live in mise (see modules/apps/mise.nix). The `docker
    # compose` / `docker buildx` subcommands only resolve when a `docker-<cmd>`
    # binary sits in docker's cli-plugins dir (DOCKER_CONFIG=$XDG_CONFIG_HOME/docker
    # per conf.d/zsh/exports.zsh), so point user-dir plugins there. docker derives
    # the subcommand from the symlink filename (docker-compose -> "compose").
    #
    # macOS ONLY. This is the colima-based docker host. Linux hosts use system
    # (apt) docker with its own plugins in /usr/lib/docker/cli-plugins; the user
    # dir outranks those, so a symlink here whose mise target isn't installed yet
    # would be a broken plugin that SHADOWS the working system one and breaks
    # `docker compose` on those servers. Keep Linux on its system docker plugins.
    #
    # We point at the real install binary, NOT the mise shim: shims dispatch on
    # argv[0], and the aqua packages name their bins docker-cli-plugin-docker-*,
    # so a shim invoked through a docker-buildx-named symlink isn't recognised
    # and mise falls through to whatever docker-buildx is next on PATH. The
    # installs/<tool>/latest symlink is maintained by mise across upgrades.
    # mkOutOfStoreSymlink because these live outside the nix store. (Install dir
    # names differ: compose uses the registry short name, buildx the explicit
    # aqua backend — see mise.nix.)
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      "docker/cli-plugins/docker-compose".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/mise/installs/docker-compose/latest/docker-cli-plugin-docker-compose";
      "docker/cli-plugins/docker-buildx".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/mise/installs/aqua-docker-buildx/latest/docker-cli-plugin-docker-buildx";
    };
  };
}
