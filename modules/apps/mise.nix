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
        # aube: jdx's Rust npm pkg manager — the backend for `npm:` global tools
        # (see npm.package_manager below). Declared here so the binary is present
        # before any npm: tool tries to install through it. Lifecycle scripts are
        # jailed by default; the current tool set was audited and none need a build
        # approval (oxfmt ships platform binaries via optionalDependencies;
        # codegraph is pure JS; protobufjs/aws-sdk postinstalls are dev-only no-ops;
        # nub's postinstall is only needed for install-as-root-then-drop-privileges,
        # see its entry below).
        aube = "latest";
        python = "latest";
        uv = "latest";
        node = "latest";
        # Tombi publishes musl-only Linux assets; the GitHub backend selects the
        # available release even though the global libc setting remains gnu.
        "github:tombi-toml/tombi" = {
          version = "latest";
          exe = "tombi";
        };
        # nub: Rust front-end for the Node toolchain — replaces npm/pnpm run, npx,
        # nvm/fnm, tsx/ts-node and nodemon with one binary. Not a runtime: it
        # provisions and execs real node, so `node` above is a hard dependency (the
        # launcher is a shell script that execs `node`; without it you get
        # "exec: node: not found"). Registry name resolves to npm:@nubjs/nub —
        # do NOT write `npm:nub`, that name belongs to an unrelated 2013 package
        # ("Uniqueness functions" by substack).
        #
        # It ships a postinstall, which aube jails. Harmless here: the script only
        # chmod +x's the platform binary at install time for the container pattern
        # where npm installs as root and the image then drops to a non-root user.
        # When installer and user are the same person (mise on a workstation),
        # bin/launch.js does the same chmod at runtime. Verified in an isolated
        # MISE_DATA_DIR: nub/nubx 0.6.0 both report versions, `nub run` executes a
        # package.json script, and `nub file.ts` transpiles and runs without a
        # separate loader — all with the postinstall jailed.
        nub = "latest";
        # ruby = "latest";
        go = "latest";
        usage = "latest";
        cargo-binstall = "latest";
        # shuck: shell linter/formatter/LSP server (Rust). cargo-binstall pulls the
        # prebuilt cargo-dist release binary, so no rustc compile; arm64 linux
        # (gnu+musl) and aarch64-darwin are both covered. Replaces the node-based
        # bash-language-server in the node-free toolchain.
        "cargo:shuck-cli" = "latest";
        "cargo:tuicr" = "latest";
        "go:github.com/go-delve/delve/cmd/dlv" = "latest";
        "go:github.com/golangci/golangci-lint/v2/cmd/golangci-lint" = "latest";
        "go:github.com/perplexityai/bumblebee/cmd/bumblebee" = "latest";
        "go:github.com/retlehs/quien" = "latest";
        "go:golang.org/x/tools/cmd/goimports" = "latest";
        "go:golang.org/x/tools/gopls" = "latest";
        "go:golang.org/x/vuln/cmd/govulncheck" = "latest";
        "go:mvdan.cc/gofumpt" = "latest";
        "npm:@rivolink/leaf" = "latest";
        "github:immanuwell/dockerfile-roast" = {
          version = "latest";
          exe = "droast";
        };
      }
      # Docker CLI plugins are managed by mise on macOS ONLY (the cli-plugins
      # wiring lives in modules/runtime/mise.nix, also Darwin-gated). Linux hosts
      # use the distro's system docker for the whole client+daemon stack, so mise must not
      # manage compose/buildx there. buildx isn't in mise's registry, so its
      # backend is named explicitly; compose's registry default moved from the
      # deprecated aqua backend to github, so it's pinned to github:docker/compose
      # to match (a bare "docker-compose" key still resolves to aqua and warns).
      # nixpkgs can lag upstream buildx, hence mise rather than a nix package.
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        "github:docker/compose" = "latest";
        "aqua:docker/buildx" = "latest";

        # code agents tools
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
        github = {
          credential_command = "gh auth token";
        };
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

  # Generate mise's shell hooks without smartcache. Order 1010 keeps this after
  # the cached integrations at 1000 and before the custom hooks at 1050.
  zsh.initContent = lib.mkOrder 1010 ''
    eval "$(${lib.getExe pkgs.mise} activate zsh)"
    # The native wrapper may create _mise after compinit on its first run.
    if (( $+functions[compdef] )) && [[ -r "$XDG_DATA_HOME/zsh/site-functions/_mise" ]]; then
      autoload -Uz _mise
      compdef _mise mise
    fi
  '';
}
