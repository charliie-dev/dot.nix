{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  enableSecrets ? false,
  ...
}:
let
  nvimdots_url = "charliie-dev/nvimdots.lua.git";
  inherit (import "${src}/modules/apps/_common.nix" { inherit pkgs; }) common_apps;
  role_pkgs = lib.concatMap (
    r: (import "${src}/modules/apps/roles/${r}.nix" { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);

  # Auto-discover program modules from modules/apps/.
  # Convention: <name>.nix returns { <name> = {...}; }; helpers prefix with _;
  # disabled modules use .bak suffix.
  appsDir = "${src}/modules/apps";
  appFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
  ) (builtins.readDir appsDir);
  appArgs = {
    inherit
      config
      pkgs
      lib
      src
      ;
  };
  loadApp =
    filename:
    let
      raw = import "${appsDir}/${filename}";
      module = if lib.isFunction raw then raw appArgs else raw;
    in
    if lib.isAttrs module && module != { } then
      module
    else
      throw "modules/apps/${filename}: expected non-empty attrset, got ${builtins.typeOf module}";
  appModules = map loadApp (builtins.attrNames appFiles);
in
lib.mkMerge [
  {
    inherit (import "${src}/modules/nix-config.nix" { inherit pkgs; }) nix;

    manual = {
      manpages.enable = false;
      json.enable = false;
      html.enable = false;
    };

    home = {
      packages = merged_pkgs;
      shell.enableZshIntegration = true;
      sessionPath = [
        "/nix/var/nix/profiles/default/bin"
        "${config.home.homeDirectory}/.local/share/mise/bin"
        "${config.home.homeDirectory}/.local/share/topgrade/bin"
      ];
      sessionVariables = {
        # Disable Determinate Nix telemetry
        # https://docs.determinate.systems/guides/telemetry/
        NIX_SENTRY_ENDPOINT = "";
        DETSYS_IDS_TELEMETRY = "disabled";
      };
      file = {
        ".config/parallel/will-cite" = {
          text = "";
        };
        ".config/terraform/terraformrc" = {
          text = ''
            plugin_cache_dir   = "$HOME/.local/share/terraform/plugin-cache"
            disable_checkpoint = true
          '';
        };
        ".config/tirith/policy.yaml" = {
          source = "${src}/conf.d/tirith/policy.yaml";
        };
        "self-made commands" = {
          enable = true;
          recursive = true;
          executable = true;
          # 1. don't quote "../conf.d/Usercommand" for `source` needs to be `absolute path`
          # 2. use "${config.xdg.configHome}/home-manager/conf.d/Usercommand" will need to use `home-manager switch --impure`
          source = "${src}/conf.d/Usercommand";
          target = ".local/bin";
        };
      };
      activation = {
        nvimdotsClone = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          if [ ! -d ${config.xdg.configHome}/nvim ]; then
            ${pkgs.git}/bin/git clone https://github.com/${nvimdots_url} ${config.xdg.configHome}/nvim
          fi
          cd ${config.xdg.configHome}/nvim
          ${pkgs.git}/bin/git remote set-url origin git@github.com:${nvimdots_url}
        '';
        initDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # SSH
          mkdir -p ${config.home.homeDirectory}/.ssh
          chmod 700 ${config.home.homeDirectory}/.ssh

          # GPG
          mkdir -p ${config.xdg.dataHome}/gnupg
          chmod 700 ${config.xdg.dataHome}/gnupg
          if [ -n "$(ls -A ${config.xdg.dataHome}/gnupg/ 2>/dev/null)" ]; then
            chmod 600 ${config.xdg.dataHome}/gnupg/*
          fi

          # Tool data dirs
          mkdir -p ${config.xdg.dataHome}/dotnet
          mkdir -p ${config.xdg.dataHome}/aws
        '';
        topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
            mkdir -p ${config.xdg.configHome}/topgrade.d
            cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
          fi
        '';
        # Pull the latest mise upstream binary into $HOME/.local/share/mise/bin.
        # The stub in pkgs.mise (defined in flake.nix) just delegates here, so
        # `mise activate` and the CLI both resolve to whatever this hook
        # installed last. Skips the download silently when network is down or
        # the binary is already current.
        # mise --version prints "<VERSION> <ARCH> (<DATE>)", first field is version.
        upgradeMise = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          (
            PATH="${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.curl
                pkgs.gnutar
                pkgs.gzip
                pkgs.gawk
              ]
            }:$PATH"
            set -eu
            case "$(uname -s)/$(uname -m)" in
              Darwin/arm64)              arch=macos-arm64 ;;
              Darwin/x86_64)             arch=macos-x64 ;;
              Linux/x86_64)              arch=linux-x64-musl ;;
              Linux/aarch64|Linux/arm64) arch=linux-arm64-musl ;;
              *)
                echo "mise upgrade: unsupported $(uname -ms), skipping" >&2
                exit 0
                ;;
            esac
            install_dir=${config.home.homeDirectory}/.local/share/mise/bin
            installed_bin=$install_dir/mise
            tmpdir=$(mktemp -d)
            trap 'rm -rf "$tmpdir"' EXIT
            http_code=$(
              curl -sS --max-time 10 -o "$tmpdir/release.json" -w '%{http_code}' \
                https://api.github.com/repos/jdx/mise/releases/latest 2>/dev/null
            ) || http_code=000
            case "$http_code" in
              200) ;;
              403)
                echo "mise upgrade: GitHub rate limit hit (HTTP 403), skipping" >&2
                exit 0 ;;
              000)
                echo "mise upgrade: GitHub API unreachable (offline?), skipping" >&2
                exit 0 ;;
              *)
                echo "mise upgrade: GitHub API returned HTTP $http_code, skipping" >&2
                exit 0 ;;
            esac
            latest=$(awk -F'"' '/"tag_name":/ { sub(/^v/, "", $4); print $4; exit }' "$tmpdir/release.json")
            if [ -z "''${latest:-}" ]; then
              echo "mise upgrade: failed to parse latest tag, skipping" >&2
              exit 0
            fi
            installed=""
            if [ -x "$installed_bin" ]; then
              installed=$("$installed_bin" --version 2>/dev/null | awk 'NR==1 { print $1 }') || true
            fi
            if [ "$installed" = "$latest" ]; then
              exit 0
            fi
            echo "mise upgrade: ''${installed:-(none)} -> $latest"
            url="https://github.com/jdx/mise/releases/download/v$latest/mise-v$latest-$arch.tar.gz"
            if ! curl -fsSL --max-time 60 "$url" -o "$tmpdir/mise.tar.gz"; then
              echo "mise upgrade: download failed, keeping current $installed" >&2
              exit 0
            fi
            tar -xzf "$tmpdir/mise.tar.gz" -C "$tmpdir"
            mkdir -p "$install_dir"
            # Atomic replace: write to sibling tempfile + mv -f. Truncating
            # in place could SIGBUS / ETXTBSY a running mise process.
            install -m 755 "$tmpdir/mise/bin/mise" "$install_dir/.mise.new"
            mv -f "$install_dir/.mise.new" "$installed_bin"
          ) || echo "mise upgrade: skipped (subshell exit $?)" >&2
        '';
        # topgrade --version prints "topgrade <VERSION>", second field is version.
        upgradeTopgrade = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          (
            PATH="${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.curl
                pkgs.gnutar
                pkgs.gzip
                pkgs.gawk
              ]
            }:$PATH"
            set -eu
            case "$(uname -s)/$(uname -m)" in
              Darwin/arm64)              arch=aarch64-apple-darwin ;;
              Darwin/x86_64)             arch=x86_64-apple-darwin ;;
              Linux/x86_64)              arch=x86_64-unknown-linux-musl ;;
              Linux/aarch64|Linux/arm64) arch=aarch64-unknown-linux-musl ;;
              *)
                echo "topgrade upgrade: unsupported $(uname -ms), skipping" >&2
                exit 0
                ;;
            esac
            install_dir=${config.home.homeDirectory}/.local/share/topgrade/bin
            installed_bin=$install_dir/topgrade
            tmpdir=$(mktemp -d)
            trap 'rm -rf "$tmpdir"' EXIT
            http_code=$(
              curl -sS --max-time 10 -o "$tmpdir/release.json" -w '%{http_code}' \
                https://api.github.com/repos/topgrade-rs/topgrade/releases/latest 2>/dev/null
            ) || http_code=000
            case "$http_code" in
              200) ;;
              403)
                echo "topgrade upgrade: GitHub rate limit hit (HTTP 403), skipping" >&2
                exit 0 ;;
              000)
                echo "topgrade upgrade: GitHub API unreachable (offline?), skipping" >&2
                exit 0 ;;
              *)
                echo "topgrade upgrade: GitHub API returned HTTP $http_code, skipping" >&2
                exit 0 ;;
            esac
            latest=$(awk -F'"' '/"tag_name":/ { sub(/^v/, "", $4); print $4; exit }' "$tmpdir/release.json")
            if [ -z "''${latest:-}" ]; then
              echo "topgrade upgrade: failed to parse latest tag, skipping" >&2
              exit 0
            fi
            installed=""
            if [ -x "$installed_bin" ]; then
              installed=$("$installed_bin" --version 2>/dev/null | awk 'NR==1 { print $2 }') || true
            fi
            if [ "$installed" = "$latest" ]; then
              exit 0
            fi
            echo "topgrade upgrade: ''${installed:-(none)} -> $latest"
            url="https://github.com/topgrade-rs/topgrade/releases/download/v$latest/topgrade-v$latest-$arch.tar.gz"
            if ! curl -fsSL --max-time 60 "$url" -o "$tmpdir/topgrade.tar.gz"; then
              echo "topgrade upgrade: download failed, keeping current $installed" >&2
              exit 0
            fi
            tar -xzf "$tmpdir/topgrade.tar.gz" -C "$tmpdir"
            mkdir -p "$install_dir"
            # Atomic replace: same rationale as mise above.
            install -m 755 "$tmpdir/topgrade" "$install_dir/.topgrade.new"
            mv -f "$install_dir/.topgrade.new" "$installed_bin"
          ) || echo "topgrade upgrade: skipped (subshell exit $?)" >&2
        '';
      };
    };

    inherit
      (import "${src}/modules/xdg-config.nix" {
        inherit
          config
          pkgs
          lib
          src
          ;
      })
      xdg
      ;
    inherit (import "${src}/modules/catppuccin.nix") catppuccin;

    programs = lib.mkMerge appModules;

    services = {
      inherit (import "${src}/modules/services/home-manager.nix" { }) home-manager;
    };
  }
  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents = import "${src}/modules/services/colima.nix" { inherit config pkgs; };
  })
  (lib.mkIf enableSecrets (
    let
      sopsConfig = import "${src}/modules/sops.nix" { inherit config src; };
      dopplerConfig = import "${src}/modules/doppler.nix" { inherit config pkgs lib; };
    in
    {
      inherit (sopsConfig) sops;

      home = {
        inherit (dopplerConfig.doppler) packages;
        activation = dopplerConfig.doppler.activation // {
          ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
            if [ -f ${config.home.homeDirectory}/.ssh/id_ed25519.pub ]; then
              if [ ! -f ${config.home.homeDirectory}/.ssh/authorized_keys ]; then
                touch ${config.home.homeDirectory}/.ssh/authorized_keys
              fi
              # Compare key type + body (cols 1-2), ignoring the comment field
              read -r ktype kbody _ < ${config.home.homeDirectory}/.ssh/id_ed25519.pub
              if ! grep -qF "$ktype $kbody" ${config.home.homeDirectory}/.ssh/authorized_keys; then
                cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub >> ${config.home.homeDirectory}/.ssh/authorized_keys
              fi
            fi
          '';
        };
      };

      programs = {
        git.signing.key = "${config.sops.secrets.ssh_ed25519_pub.path}";
        git.settings.gpg.ssh.allowedSignersFile = "${config.sops.secrets.allowed_signers.path}";
        ssh.matchBlocks."*".identityFile = "${config.sops.secrets.ssh_ed25519.path}";
        zsh.envExtra = ''
          # Load Doppler secrets (application-layer)
          if [ -r "${config.xdg.dataHome}/doppler/env" ]; then
            set -a
            source "${config.xdg.dataHome}/doppler/env"
            set +a
          fi
        '';
      };
    }
  ))
]
