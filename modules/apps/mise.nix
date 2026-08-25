{
  pkgs,
  lib,
  ...
}:
{
  mise = {
    enable = true;
    enableZshIntegration = false; # activated below without smartcache
    globalConfig = {
      tools = {
        # Runtimes and package managers
        aube = "latest"; # npm backend; lifecycle scripts stay jailed
        cargo-binstall = "latest"; # install cargo tools from prebuilt releases
        go = "latest";
        node = "latest"; # runtime for npm tools and nub
        python = "latest";
        uv = "latest";

        # LSP
        "aqua:LuaLS/lua-language-server" = "latest";
        "aqua:artempyanykh/marksman" = "latest";
        "aqua:astral-sh/ruff" = "latest";
        "aqua:hashicorp/terraform-ls" = "latest";
        "aqua:terraform-linters/tflint" = "latest";
        "cargo:shuck-cli" = "latest"; # shell LSP and linter; replaces bash-language-server
        "github:kristoff-it/superhtml" = "latest"; # HTML LSP and formatter
        "github:neocmakelsp/neocmakelsp" = "latest";
        "github:tombi-toml/tombi" = {
          version = "latest";
          exe = "tombi";
        }; # musl-only Linux releases
        "go:golang.org/x/tools/gopls" = "latest";
        "npm:@actions/languageserver" = "latest";
        "npm:dockerfile-language-server-nodejs" = "latest";
        "npm:vscode-langservers-extracted" = "latest";
        "npm:yaml-language-server" = "latest";
        "pipx:zuban" = "latest";

        # Formatters
        "aqua:JohnnyMorganz/StyLua" = "latest";
        "cargo:shellharden" = "latest";
        "go:golang.org/x/tools/cmd/goimports" = "latest";
        "go:mvdan.cc/gofumpt" = "latest";
        "npm:fixjson" = "latest";
        "npm:prettier" = "latest";
        "pipx:beautysh" = "latest";
        "pipx:cmakelang" = {
          version = "latest";
          extras = "YAML";
        }; # cmake-format with YAML config support

        # Linters
        "aqua:hadolint/hadolint" = "latest";
        "aqua:koalaman/shellcheck" = "latest";
        "aqua:rhysd/actionlint" = "latest";
        "github:immanuwell/dockerfile-roast" = {
          version = "latest";
          exe = "droast";
        }; # Dockerfile linter
        "go:github.com/golangci/golangci-lint/v2/cmd/golangci-lint" = "latest";
        "npm:markdownlint-cli2" = "latest";
        "npm:oxlint" = "latest";
        "pipx:systemdlint" = "latest";

        # DAP
        "github:vadimcn/codelldb" = {
          version = "latest";
          bin_path = "extension/adapter";
        }; # executable is nested in the release archive
        "go:github.com/go-delve/delve/cmd/dlv" = "latest";

        # General CLI tools
        nub = "latest"; # Node toolchain frontend; requires node
        usage = "latest";
        # ruby = "latest";
        "cargo:tuicr" = "latest";
        "go:github.com/perplexityai/bumblebee/cmd/bumblebee" = "latest";
        "go:github.com/retlehs/quien" = "latest";
        "go:golang.org/x/vuln/cmd/govulncheck" = "latest"; # project-wide Go vulnerability scanner
        "npm:@rivolink/leaf" = "latest";
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        "github:docker/compose" = "latest"; # avoid the deprecated aqua alias
        "aqua:docker/buildx" = "latest"; # nixpkgs can lag upstream

        # Code agent tools
        "github:DeusData/codebase-memory-mcp" = "latest";
        "npm:@colbymchenry/codegraph" = "latest";
        "npm:@google-cloud/backupdr-mcp" = "latest";
        "npm:@google-cloud/gcloud-mcp" = "latest";
        "npm:@google-cloud/observability-mcp" = "latest";
        "npm:@google-cloud/storage-mcp" = "latest";
        "npm:@hackmd/hackmd-cli" = "latest";
        "npm:@readwise/cli" = "latest";
        "npm:ctx7" = "latest";
        "npm:tokscale" = "latest";
        "npm:@earendil-works/pi-coding-agent" = "latest";
      };
      settings = {
        # https://mise.jdx.dev/configuration/settings.html

        always_keep_download = false;
        always_keep_install = false;
        auto_install = true; # install missing tools on execution
        color_theme = "catppuccin";
        env_file = ".env";
        experimental = true;
        github = {
          credential_command = "gh auth token";
        };
        gpg_verify = true;
        jobs = 8;
        libc = "gnu"; # avoid mise's musl host misdetection
        minimum_release_age = "0s"; # duration string; integer 0 is invalid
        paranoid = false;
        use_versions_host = false; # bypass the flaky mise-versions CDN
        task = {
          output = "keep-order";
        };

        cargo = {
          binstall = true;
        };

        npm = {
          package_manager = "aube";
        };

        python = {
          uv_venv_auto = true;
        };

        # config files with these prefixes will be trusted by default
        trusted_config_paths = [
          "~/.config/mise"
          "~/.config/nvim"
          "~/.config/home-manager"
          "/opt/stacks"
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

  # Load mise without smartcache after cached integrations and before custom hooks.
  zsh.initContent = lib.mkOrder 1010 ''
    eval "$(${lib.getExe pkgs.mise} activate zsh)"
    # The native wrapper may create _mise after compinit on its first run.
    if (( $+functions[compdef] )) && [[ -r "$XDG_DATA_HOME/zsh/site-functions/_mise" ]]; then
      autoload -Uz _mise
      compdef _mise mise
    fi
  '';
}
