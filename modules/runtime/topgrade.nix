{
  config,
  pkgs,
  lib,
  src,
  ...
}:
{
  home.activation = {
    # Intentionally copy only once: each host owns its mutable overrides.
    topgradeCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
        mkdir -p ${config.xdg.configHome}/topgrade.d
        cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
      fi
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
        latest=$(grep -o '"tag_name": *"v[^"]*"' "$tmpdir/release.json" | grep -o 'v[^"]*' | sed 's/^v//')
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
}
