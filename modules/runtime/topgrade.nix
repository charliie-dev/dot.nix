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
      (
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          exit 0
        fi
        if [ ! -f ${config.xdg.configHome}/topgrade.d/disable.toml ]; then
          mkdir -p ${config.xdg.configHome}/topgrade.d
          cp "${src}/conf.d/topgrade/disable.toml" ${config.xdg.configHome}/topgrade.d/disable.toml
        fi
      )
    '';

    # topgrade --version prints "topgrade <VERSION>", second field is version.
    upgradeTopgrade = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          exit 0
        fi

        PATH="${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnutar
            pkgs.gzip
            pkgs.gawk
            pkgs.jq
            pkgs.util-linux
          ]
        }:$PATH"
        set -eu
        umask 077
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

        repo=topgrade-rs/topgrade
        api_url="https://api.github.com/repos/$repo/releases/latest"
        install_dir=${config.home.homeDirectory}/.local/share/topgrade/bin
        installed_bin=$install_dir/topgrade
        lock_dir=${config.xdg.stateHome}/home-manager/locks
        lock_path=$lock_dir/topgrade-upgrade.lock
        if [ -L "$lock_dir" ] || { [ -e "$lock_dir" ] && [ ! -d "$lock_dir" ]; }; then
          echo "topgrade upgrade: unsafe lock directory $lock_dir" >&2
          exit 1
        fi
        mkdir -p "$lock_dir"
        chmod 700 "$lock_dir"
        if [ -L "$lock_path" ] || { [ -e "$lock_path" ] && [ ! -f "$lock_path" ]; }; then
          echo "topgrade upgrade: unsafe lock path $lock_path" >&2
          exit 1
        fi
        exec 9>> "$lock_path"
        if [ -L "$lock_path" ] || [ ! -f "$lock_path" ]; then
          echo "topgrade upgrade: unsafe lock path $lock_path" >&2
          exit 1
        fi
        flock 9

        tmpdir=$(mktemp -d)
        new_bin=""
        trap 'rm -rf "$tmpdir"; [ -z "$new_bin" ] || rm -f "$new_bin"' EXIT HUP INT TERM

        if ! http_code=$(
          curl -sS --max-time 10 -o "$tmpdir/release.json" -w '%{http_code}' \
            "$api_url" 2>/dev/null
        ); then
          echo "topgrade upgrade: GitHub API unreachable (offline or timeout), skipping" >&2
          exit 0
        fi
        case "$http_code" in
          200) ;;
          403|429)
            echo "topgrade upgrade: GitHub rate limit hit (HTTP $http_code), skipping" >&2
            exit 0
            ;;
          5??)
            echo "topgrade upgrade: GitHub API unavailable (HTTP $http_code), skipping" >&2
            exit 0
            ;;
          *)
            echo "topgrade upgrade: unexpected GitHub API response (HTTP $http_code)" >&2
            exit 1
            ;;
        esac

        if ! tag=$(jq -er '
          if type == "object"
            and (.tag_name | type == "string")
            and (.tag_name | test("^v[0-9A-Za-z][0-9A-Za-z._+-]*$"))
            and (.assets | type == "array")
          then .tag_name
          else error("invalid release metadata")
          end
        ' "$tmpdir/release.json"); then
          echo "topgrade upgrade: malformed GitHub release metadata" >&2
          exit 1
        fi
        latest=''${tag#v}
        asset_name="topgrade-$tag-$arch.tar.gz"
        expected_url="https://github.com/$repo/releases/download/$tag/$asset_name"

        if ! asset=$(jq -cer \
          --arg tag "$tag" \
          --arg name "$asset_name" \
          --arg url "$expected_url" '
          if .tag_name != $tag then
            error("release tag changed")
          else
            [.assets[] | select(.name == $name)] as $matches
            | if ($matches | length) != 1 then
                error("expected exactly one matching asset")
              else
                $matches[0]
                | if (.browser_download_url == $url)
                    and (.digest | type == "string")
                    and (.digest | test("^sha256:[0-9A-Fa-f]{64}$"))
                  then {
                    browser_download_url: .browser_download_url,
                    digest: (.digest | ascii_downcase)
                  }
                  else error("invalid asset metadata")
                  end
              end
          end
        ' "$tmpdir/release.json"); then
          echo "topgrade upgrade: missing, duplicate, or malformed metadata for $asset_name" >&2
          exit 1
        fi
        url=$(printf '%s' "$asset" | jq -er '.browser_download_url')
        expected_digest=$(printf '%s' "$asset" | jq -er '.digest | sub("^sha256:"; "")')

        installed=""
        if [ -x "$installed_bin" ]; then
          installed=$("$installed_bin" --version 2>/dev/null | awk 'NR==1 { print $2 }') || true
        fi
        if [ "$installed" = "$latest" ]; then
          exit 0
        fi
        echo "topgrade upgrade: ''${installed:-(none)} -> $latest"

        archive=$tmpdir/$asset_name
        if ! curl -fsSL --max-time 60 "$url" -o "$archive"; then
          echo "topgrade upgrade: download unavailable, keeping current ''${installed:-(none)}" >&2
          exit 0
        fi
        actual_digest=$(sha256sum "$archive" | awk '{ print $1 }')
        if [ "$actual_digest" != "$expected_digest" ]; then
          echo "topgrade upgrade: sha256 mismatch for $asset_name; keeping current ''${installed:-(none)}" >&2
          exit 1
        fi

        if ! tar -tzf "$archive" > "$tmpdir/members" \
          || ! awk '
            $0 != "topgrade" { valid = 0 }
            $0 == "topgrade" { count++ }
            END { exit !(valid != 0 && count == 1) }
          ' valid=1 "$tmpdir/members" \
          || ! tar -tvzf "$archive" | awk '
            substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { valid = 0 }
            END { exit !(valid != 0) }
          ' valid=1; then
          echo "topgrade upgrade: unexpected or unsafe archive layout" >&2
          exit 1
        fi

        mkdir "$tmpdir/extract"
        if ! tar --extract --gzip --file "$archive" --directory "$tmpdir/extract" \
          --no-same-owner --no-same-permissions; then
          echo "topgrade upgrade: archive extraction failed" >&2
          exit 1
        fi
        extracted_bin=$tmpdir/extract/topgrade
        if [ ! -f "$extracted_bin" ] || [ -L "$extracted_bin" ] || [ ! -x "$extracted_bin" ]; then
          echo "topgrade upgrade: archive lacks regular executable topgrade" >&2
          exit 1
        fi

        mkdir -p "$install_dir"
        new_bin=$(mktemp "$install_dir/.topgrade.new.XXXXXX")
        install -m 755 "$extracted_bin" "$new_bin"
        mv -f "$new_bin" "$installed_bin"
        new_bin=""
      )
    '';
  };
}
