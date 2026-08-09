{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Docker CLI plugins live in mise (see modules/apps/mise.nix). The `docker
  # compose` / `docker buildx` subcommands only resolve when a `docker-<cmd>`
  # binary sits in docker's cli-plugins dir (DOCKER_CONFIG=$XDG_CONFIG_HOME/docker
  # per home.sessionVariables), so point user-dir plugins there. docker derives
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
  xdg.configFile = lib.optionalAttrs pkgs.stdenv.isDarwin {
    "docker/cli-plugins/docker-compose".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/mise/installs/docker-compose/latest/docker-cli-plugin-docker-compose";
    "docker/cli-plugins/docker-buildx".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/mise/installs/aqua-docker-buildx/latest/docker-cli-plugin-docker-buildx";
  };

  home.activation.upgradeMise = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Pull the latest mise upstream binary into $HOME/.local/share/mise/bin.
    # The stub in pkgs.mise (defined in flake.nix) just delegates here, so
    # `mise activate` and the CLI both resolve to whatever this hook installed
    # last. Skips the download silently when network is down or the binary is
    # already current. `mise --version` prints "<VERSION> <ARCH> (<DATE>)".
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
      latest=$(grep -o '"tag_name": *"v[^"]*"' "$tmpdir/release.json" | grep -o 'v[^"]*' | sed 's/^v//')
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
      # Atomic replace: write to sibling tempfile + mv -f. Truncating in place
      # could SIGBUS / ETXTBSY a running mise process.
      install -m 755 "$tmpdir/mise/bin/mise" "$install_dir/.mise.new"
      mv -f "$install_dir/.mise.new" "$installed_bin"
    ) || echo "mise upgrade: skipped (subshell exit $?)" >&2

    # The mise stub package only ships bin/mise, so the upstream _mise
    # completion never lands in the Nix profile FPATH. Regenerate it against
    # the freshly-synced binary so completion versions cannot drift.
    (
      set -eu
      installed_bin=${config.home.homeDirectory}/.local/share/mise/bin/mise
      completion_dir=${config.xdg.dataHome}/zsh/site-functions
      [ -x "$installed_bin" ] || exit 0
      mkdir -p "$completion_dir"
      tmp="$completion_dir/.mise.completion.new"
      if "$installed_bin" completion zsh >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$completion_dir/_mise"
      else
        rm -f "$tmp"
      fi
    ) || echo "mise completion: skipped (subshell exit $?)" >&2
  '';
}
