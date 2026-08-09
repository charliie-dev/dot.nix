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
    # last. Offline, timeout, and rate-limit failures are availability events;
    # release metadata, digest, or archive failures are fatal integrity errors.
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
        Darwin/arm64)              arch=macos-arm64 ;;
        Darwin/x86_64)             arch=macos-x64 ;;
        Linux/x86_64)              arch=linux-x64-musl ;;
        Linux/aarch64|Linux/arm64) arch=linux-arm64-musl ;;
        *)
          echo "mise upgrade: unsupported $(uname -ms), skipping" >&2
          exit 0
          ;;
      esac

      repo=jdx/mise
      api_url="https://api.github.com/repos/$repo/releases/latest"
      install_dir=${config.home.homeDirectory}/.local/share/mise/bin
      installed_bin=$install_dir/mise
      lock_dir=${config.xdg.stateHome}/home-manager/locks
      lock_path=$lock_dir/mise-upgrade.lock
      if [ -L "$lock_dir" ] || { [ -e "$lock_dir" ] && [ ! -d "$lock_dir" ]; }; then
        echo "mise upgrade: unsafe lock directory $lock_dir" >&2
        exit 1
      fi
      mkdir -p "$lock_dir"
      chmod 700 "$lock_dir"
      if [ -L "$lock_path" ] || { [ -e "$lock_path" ] && [ ! -f "$lock_path" ]; }; then
        echo "mise upgrade: unsafe lock path $lock_path" >&2
        exit 1
      fi
      exec 9>> "$lock_path"
      if [ -L "$lock_path" ] || [ ! -f "$lock_path" ]; then
        echo "mise upgrade: unsafe lock path $lock_path" >&2
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
        echo "mise upgrade: GitHub API unreachable (offline or timeout), skipping" >&2
        exit 0
      fi
      case "$http_code" in
        200) ;;
        403|429)
          echo "mise upgrade: GitHub rate limit hit (HTTP $http_code), skipping" >&2
          exit 0
          ;;
        5??)
          echo "mise upgrade: GitHub API unavailable (HTTP $http_code), skipping" >&2
          exit 0
          ;;
        *)
          echo "mise upgrade: unexpected GitHub API response (HTTP $http_code)" >&2
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
        echo "mise upgrade: malformed GitHub release metadata" >&2
        exit 1
      fi
      latest=''${tag#v}
      asset_name="mise-$tag-$arch.tar.gz"
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
        echo "mise upgrade: missing, duplicate, or malformed metadata for $asset_name" >&2
        exit 1
      fi
      url=$(printf '%s' "$asset" | jq -er '.browser_download_url')
      expected_digest=$(printf '%s' "$asset" | jq -er '.digest | sub("^sha256:"; "")')

      installed=""
      if [ -x "$installed_bin" ]; then
        installed=$("$installed_bin" --version 2>/dev/null | awk 'NR==1 { print $1 }') || true
      fi
      if [ "$installed" = "$latest" ]; then
        exit 0
      fi
      echo "mise upgrade: ''${installed:-(none)} -> $latest"

      archive=$tmpdir/$asset_name
      if ! curl -fsSL --max-time 60 "$url" -o "$archive"; then
        echo "mise upgrade: download unavailable, keeping current ''${installed:-(none)}" >&2
        exit 0
      fi
      actual_digest=$(sha256sum "$archive" | awk '{ print $1 }')
      if [ "$actual_digest" != "$expected_digest" ]; then
        echo "mise upgrade: sha256 mismatch for $asset_name; keeping current ''${installed:-(none)}" >&2
        exit 1
      fi

      if ! tar -tzf "$archive" > "$tmpdir/members" \
        || ! awk '
          $0 !~ /^mise(\/|$)/ { valid = 0 }
          {
            parts = split($0, component, "/")
            for (i = 1; i <= parts; i++) {
              if (component[i] == "..") valid = 0
            }
          }
          $0 == "mise/bin/mise" { count++ }
          END { exit !(valid != 0 && count == 1) }
        ' valid=1 "$tmpdir/members" \
        || ! tar -tvzf "$archive" | awk '
          substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { valid = 0 }
          END { exit !(valid != 0) }
        ' valid=1; then
        echo "mise upgrade: unexpected or unsafe archive layout" >&2
        exit 1
      fi

      mkdir "$tmpdir/extract"
      if ! tar --extract --gzip --file "$archive" --directory "$tmpdir/extract" \
        --no-same-owner --no-same-permissions; then
        echo "mise upgrade: archive extraction failed" >&2
        exit 1
      fi
      extracted_bin=$tmpdir/extract/mise/bin/mise
      if [ ! -f "$extracted_bin" ] || [ -L "$extracted_bin" ] || [ ! -x "$extracted_bin" ]; then
        echo "mise upgrade: archive lacks regular executable mise/bin/mise" >&2
        exit 1
      fi

      mkdir -p "$install_dir"
      new_bin=$(mktemp "$install_dir/.mise.new.XXXXXX")
      install -m 755 "$extracted_bin" "$new_bin"
      mv -f "$new_bin" "$installed_bin"
      new_bin=""
    ) || exit $?

    # The mise stub package only ships bin/mise, so the upstream _mise
    # completion never lands in the Nix profile FPATH. Regenerate it against
    # the freshly-synced binary so completion versions cannot drift.
    (
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        exit 0
      fi

      PATH="${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ]
      }:$PATH"
      set -eu
      umask 077
      installed_bin=${config.home.homeDirectory}/.local/share/mise/bin/mise
      completion_dir=${config.xdg.dataHome}/zsh/site-functions
      lock_dir=${config.xdg.stateHome}/home-manager/locks
      lock_path=$lock_dir/mise-upgrade.lock
      [ -x "$installed_bin" ] || exit 0
      if [ -L "$lock_dir" ] || [ ! -d "$lock_dir" ]; then
        echo "mise completion: unsafe lock directory $lock_dir" >&2
        exit 1
      fi
      if [ -L "$lock_path" ] || [ ! -f "$lock_path" ]; then
        echo "mise completion: unsafe lock path $lock_path" >&2
        exit 1
      fi
      exec 9>> "$lock_path"
      if [ -L "$lock_path" ] || [ ! -f "$lock_path" ]; then
        echo "mise completion: unsafe lock path $lock_path" >&2
        exit 1
      fi
      flock 9

      mkdir -p "$completion_dir"
      tmp=$(mktemp "$completion_dir/.mise.completion.XXXXXX")
      trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT HUP INT TERM
      if "$installed_bin" completion zsh > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$completion_dir/_mise"
        tmp=""
      else
        echo "mise completion: generation failed, keeping current completion" >&2
      fi
    )
  '';
}
