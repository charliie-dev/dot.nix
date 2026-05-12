{
  mise = {
    enable = true;
    enableZshIntegration = false; # self-definded smartcache in conf.d/zsh
    globalConfig = {
      tools = {
        bun = "latest";
        python = "latest";
        uv = "latest";
        node = "latest";
        # ruby = "latest";
        go = "latest";
        usage = "latest";
        cargo-binstall = "latest";
        "npm:@google-cloud/backupdr-mcp" = "latest";
        "npm:@google-cloud/gcloud-mcp" = "latest";
        "npm:@google-cloud/observability-mcp" = "latest";
        "npm:@google-cloud/storage-mcp" = "latest";
        "npm:@hackmd/hackmd-cli" = "latest";
        "npm:@readwise/cli" = "latest";
        "npm:@sliday/tamp" = "latest";
        "npm:ctx7" = "latest";
        "go:github.com/go-delve/delve/cmd/dlv" = "latest";
        "go:mvdan.cc/gofumpt" = "latest";
        "go:golang.org/x/tools/cmd/goimports" = "latest";
        "go:github.com/golangci/golangci-lint/v2/cmd/golangci-lint" = "latest";
        "go:golang.org/x/tools/gopls" = "latest";
        "go:golang.org/x/vuln/cmd/govulncheck" = "latest";
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
        task = {
          output = "keep-order";
        };

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
          "/etc/docker/composes"
          "~/Workspace"
          "~/Work"
        ];

        # configure messages displayed when entering directories with config files
        status = {
          missing_tools = "if_other_versions_installed";
          show_env = false;
        };
      };
    };
  };
}
