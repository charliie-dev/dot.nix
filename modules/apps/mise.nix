{
  mise = {
    enable = true;
    enableZshIntegration = false; # self-definded smartcache in conf.d/zsh
    globalConfig = {
      tools = {
        node = "latest";
        python = "latest";
        # ruby = "latest";
        # go = "latest";
        usage = "latest";
      };
      # aliases = {
      #   my_custom_node = "20";
      # };
      # plugins = {
      #   # specify a custom repo url
      #   # note this will only be used if the plugin does not already exist
      #   perl = "https://github.com/ouest/asdf-perl";
      #   lua = "https://github.com/Stratus3D/asdf-lua";
      #   php = "https://github.com/asdf-community/asdf-php";
      # };
    };
    settings = {
      # plugins can read the versions files used by other version managers (if enabled by the plugin)
      # for example, .nvmrc in the case of node's nvm
      legacy_version_file = true;
      # legacy_version_file_disable_tools = ['python']

      # configure `mise install` to always keep the downloaded archive
      always_keep_download = false; # deleted after install by default
      always_keep_install = false; # deleted on failure by default

      plugin_autoupdate_last_check_duration = 0; # set to 0 to disable updates

      # config files with these prefixes will be trusted by default
      trusted_config_paths = [
        "~/.config/mise"
        "~/Workspace"
        "~/Work"
      ];

      verbose = false; # set to true to see full installation output, see `MISE_VERBOSE`
      asdf_compat = false; # set to true to ensure .tool-versions will be compatible with asdf, see `MISE_ASDF_COMPAT`
      # http_timeout = 30;   # set the timeout for http requests in seconds, see `MISE_HTTP_TIMEOUT`
      jobs = 4; # number of plugins or runtimes to install in parallel. The default is `4`.
      raw = false; # set to true to directly pipe plugins to stdin/stdout/stderr
      yes = false; # set to true to automatically answer yes to all prompts

      not_found_auto_install = true; # see MISE_NOT_FOUND_AUTO_INSTALL
      task_output = "prefix"; # see Tasks Runner for more information
      paranoid = false; # see MISE_PARANOID

      # shorthands_file = '~/.config/mise/shorthands.toml' # path to the shorthands file, see `MISE_SHORTHANDS_FILE`
      disable_default_shorthands = false; # disable the default shorthands, see `MISE_DISABLE_DEFAULT_SHORTHANDS`
      # disable_tools = [ "node" ]; # disable specific tools, generally used to turn off core tools

      env_file = ".env"; # load env vars from a dotenv file, see `MISE_ENV_FILE`

      experimental = true; # enable experimental features

      # configure messages displayed when entering directories with config files
      status = {
        missing_tools = "if_other_versions_installed";
        show_env = true;
        show_tools = true;
      };
    };
  };
}
