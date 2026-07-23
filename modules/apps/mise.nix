{
  pkgs,
  lib,
  ...
}:
{
  mise = {
    enable = true;
    enableZshIntegration = false; # self-definded smartcache in conf.d/zsh
    globalConfig = {
      tools = {
        bun = "latest";
        # aube: jdx's Rust npm pkg manager — the backend for `npm:` global tools
        # (see npm.package_manager below). Declared here so the binary is present
        # before any npm: tool tries to install through it. Lifecycle scripts are
        # jailed by default; the current tool set was audited and none need a build
        # approval (hunkdiff/oxfmt ship platform binaries via optionalDependencies;
        # codegraph is pure JS; protobufjs/aws-sdk postinstalls are dev-only no-ops).
        aube = "latest";
        python = "latest";
        uv = "latest";
        node = "latest";
        # ruby = "latest";
        go = "latest";
        usage = "latest";
        cargo-binstall = "latest";
        # shuck: shell linter/formatter/LSP server (Rust). cargo-binstall pulls the
        # prebuilt cargo-dist release binary, so no rustc compile; arm64 linux
        # (gnu+musl) and aarch64-darwin are both covered. Replaces the node-based
        # bash-language-server in the node-free toolchain.
        "cargo:shuck-cli" = "latest";
        "go:github.com/go-delve/delve/cmd/dlv" = "latest";
        "go:github.com/golangci/golangci-lint/v2/cmd/golangci-lint" = "latest";
        "go:github.com/perplexityai/bumblebee/cmd/bumblebee" = "latest";
        "go:github.com/retlehs/quien" = "latest";
        "go:golang.org/x/tools/cmd/goimports" = "latest";
        "go:golang.org/x/tools/gopls" = "latest";
        "go:golang.org/x/vuln/cmd/govulncheck" = "latest";
        "go:mvdan.cc/gofumpt" = "latest";
        "npm:@rivolink/leaf" = "latest";
        "npm:hunkdiff" = "latest";
        "github:immanuwell/dockerfile-roast" = {
          version = "latest";
          exe = "droast";
        };
      }
      # Docker CLI plugins are managed by mise on macOS ONLY (the cli-plugins
      # wiring lives in xdg-config.nix, also Darwin-gated). Linux hosts use the
      # distro's system docker for the whole client+daemon stack, so mise must not
      # manage compose/buildx there. buildx isn't in mise's registry, so its
      # backend is named explicitly; compose's registry default moved from the
      # deprecated aqua backend to github, so it's pinned to github:docker/compose
      # to match (a bare "docker-compose" key still resolves to aqua and warns).
      # nixpkgs lagged buildx (0.31.1 vs upstream 0.34.1), hence mise rather than
      # a nix package.
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        "github:docker/compose" = "latest";
        "aqua:docker/buildx" = "latest";

        # code agents tools
        # codebase-memory-mcp: C static binary shipped via GitHub releases.
        # `matching = "ui"` picks the embedded-UI asset
        # (codebase-memory-mcp-ui-<os>-<arch>.tar.gz) instead of the headless
        # default, so `--ui=true` can serve the HTTP dashboard; platform arch is
        # still autodetected. github backend also verifies artifact attestation.
        "github:DeusData/codebase-memory-mcp" = {
          version = "latest";
          matching = "ui";
        };
        "npm:@colbymchenry/codegraph" = "latest";
        "npm:@google-cloud/backupdr-mcp" = "latest";
        "npm:@google-cloud/gcloud-mcp" = "latest";
        "npm:@google-cloud/observability-mcp" = "latest";
        "npm:@google-cloud/storage-mcp" = "latest";
        "npm:@hackmd/hackmd-cli" = "latest";
        "npm:@readwise/cli" = "latest";
        "npm:ctx7" = "latest";
        "npm:tokscale" = "latest";
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
        libc = "gnu"; # force glibc selection; mise's static-musl binary misdetects host libc
        # duration string, not integer — mise errors on `0` ("expected a string")
        minimum_release_age = "0s";
        paranoid = false;
        # mise-versions.jdx.dev (the CDN that caches version listings) frequently
        # 403s, spamming "outcome=failed status=403 fallback=true" warnings even
        # though the source-direct fallback already succeeds. Disabling the host
        # makes mise resolve versions straight from each backend's source, so
        # `latest` keeps working without the noise. Trade-off: a few more direct
        # GitHub/aqua calls on version lookup (verified harmless for buildx).
        use_versions_host = false;
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
