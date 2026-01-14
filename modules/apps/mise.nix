{
  mise = {
    enable = true;
    enableZshIntegration = true; # self-definded smartcache in conf.d/zsh
    globalConfig = {
      tools = {
        bun = "latest";
        python = "latest";
        uv = "latest";
        # ruby = "latest";
        # go = "latest";
        usage = "latest";
        cargo-binstall = "latest";
      };
      # plugins = {
      #   # specify a custom repo url
      #   # note this will only be used if the plugin does not already exist
      #   perl = "https://github.com/ouest/asdf-perl";
      #   lua = "https://github.com/Stratus3D/asdf-lua";
      #   php = "https://github.com/asdf-community/asdf-php";
      # };
      settings = {
        # https://mise.jdx.dev/configuration/settings.html

        always_keep_download = false;
        always_keep_install = false;
        auto_install = true; # Automatically install missing tools when running `mise x`, `mise run`, or as part of the 'not found' handler.
        color_theme = "catppuccin";
        env_file = ".env";
        experimental = true;
        gpg_verify = true;
        jobs = 8;
        paranoid = false;
        task_output = "keep-order";

        npm = {
          package_manager = "bun";
        };

        python = {
          uv_venv_auto = true;
        };

        # config files with these prefixes will be trusted by default
        trusted_config_paths = [
          "~/.config/mise"
          "~/.config/nvim"
          "~/.config/home-manager"
        ];

        # configure messages displayed when entering directories with config files
        status = {
          missing_tools = "if_other_versions_installed";
          show_env = true;
        };
      };
    };
  };
}
