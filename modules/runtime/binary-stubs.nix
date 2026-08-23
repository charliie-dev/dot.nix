{ lib }:
_final: prev:
let
  runtimeInputs = [
    prev.coreutils
    prev.curl
    prev.gawk
    prev.gnutar
    prev.gzip
    prev.jq
    prev.util-linux
  ];

  mkRuntimeStub =
    {
      name,
      repo,
      arches,
      archiveMember ? null,
      assetName ? "${name}-$tag-$arch.tar.gz",
      generatedAssets ? [ ],
      installDir ? ".local/share/${name}/bin",
      installNativeAssets ? false,
    }:
    let
      root = if archiveMember == null then null else lib.head (lib.splitString "/" archiveMember);
      archCases = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (platform: arch: "          ${platform}) arch=${arch} ;;") arches
      );
      archiveNeeded =
        if installNativeAssets then
          ''[ ! -x "$target" ] || [ ! -f "$assets_stamp" ] || [ "$target" -nt "$assets_stamp" ] || [ ! -f "$man_path" ]''
        else
          ''[ ! -x "$target" ]'';
      wrapper = prev.writeShellApplication {
        inherit name runtimeInputs;
        text = ''
                    install_dir="$HOME/${installDir}"
                    target="$install_dir/${name}"
                    state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
                    lock_dir="$state_home/home-manager/locks"
                    lock_path="$lock_dir/${name}-bootstrap.lock"
          ${lib.optionalString (installNativeAssets || generatedAssets != [ ]) ''
            data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
          ''}
          ${lib.optionalString installNativeAssets ''
            assets_stamp="$state_home/home-manager/${name}-assets-version"
            assets_retry="$state_home/home-manager/${name}-assets-retry"
            man_path="$data_home/man/man1/${name}.1"
          ''}
                    umask 077
                    sync_archive() (
                      set -e
                      case "$(uname -s)/$(uname -m)" in
          ${archCases}
                        *)
                          echo "${name} bootstrap: unsupported $(uname -ms)" >&2
                          exit 1
                          ;;
                      esac

                      if [ -L "$install_dir" ] || { [ -e "$install_dir" ] && [ ! -d "$install_dir" ]; }; then
                        echo "${name} bootstrap: unsafe install directory $install_dir" >&2
                        exit 1
                      fi
                      if [ -L "$lock_dir" ] || { [ -e "$lock_dir" ] && [ ! -d "$lock_dir" ]; }; then
                        echo "${name} bootstrap: unsafe lock directory $lock_dir" >&2
                        exit 1
                      fi
                      mkdir -p "$install_dir" "$lock_dir"
                      chmod 700 "$lock_dir"
                      if [ -L "$lock_path" ] || { [ -e "$lock_path" ] && [ ! -f "$lock_path" ]; }; then
                        echo "${name} bootstrap: unsafe lock path $lock_path" >&2
                        exit 1
                      fi
                      exec 9>>"$lock_path"
                      if [ -L "$lock_path" ] || [ ! -f "$lock_path" ]; then
                        echo "${name} bootstrap: unsafe lock path $lock_path" >&2
                        exit 1
                      fi
                      flock 9
                      if ${archiveNeeded}; then
                        tmpdir=$(mktemp -d)
                        new_bin=""
                        asset_tmp=""
                        trap 'rm -rf "$tmpdir"; [ -z "$new_bin" ] || rm -f "$new_bin"; [ -z "$asset_tmp" ] || rm -f "$asset_tmp"' EXIT HUP INT TERM

                        repo=${repo}
                        requested_tag=""
                        if [ -x "$target" ]; then
                          version=$("$target" --version 2>/dev/null | awk 'NR == 1 { print $1; exit }')
                          if [[ ! "$version" =~ ^[0-9][0-9A-Za-z._+-]*$ ]]; then
                            echo "${name} bootstrap: invalid installed version" >&2
                            exit 1
                          fi
                          requested_tag="v$version"
                          api_url="https://api.github.com/repos/$repo/releases/tags/$requested_tag"
                        else
                          api_url="https://api.github.com/repos/$repo/releases/latest"
                        fi
                        http_code=$(
                          curl -sS --max-time 10 -o "$tmpdir/release.json" -w '%{http_code}' "$api_url"
                        ) || {
                          echo "${name} bootstrap: GitHub API unavailable" >&2
                          exit 1
                        }
                        if [ "$http_code" != 200 ]; then
                          echo "${name} bootstrap: GitHub API returned HTTP $http_code" >&2
                          exit 1
                        fi

                        tag=$(jq -er '
                          if type == "object"
                            and (.tag_name | type == "string")
                            and (.tag_name | test("^v[0-9A-Za-z][0-9A-Za-z._+-]*$"))
                            and (.assets | type == "array")
                          then .tag_name
                          else error("invalid release metadata")
                          end
                        ' "$tmpdir/release.json") || {
                          echo "${name} bootstrap: malformed GitHub release metadata" >&2
                          exit 1
                        }
                        if [ -n "$requested_tag" ] && [ "$tag" != "$requested_tag" ]; then
                          echo "${name} bootstrap: release tag mismatch" >&2
                          exit 1
                        fi

                        asset_name="${assetName}"
                        expected_url="https://github.com/$repo/releases/download/$tag/$asset_name"
                        expected_digest=$(jq -er \
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
                                $matches[0] as $asset
                                | if ($asset.browser_download_url == $url)
                                    and ($asset.digest | type == "string")
                                    and ($asset.digest | test("^sha256:[0-9A-Fa-f]{64}$"))
                                  then $asset.digest
                                    | ascii_downcase
                                    | sub("^sha256:"; "")
                                  else error("invalid asset metadata")
                                  end
                              end
                          end
                        ' "$tmpdir/release.json") || {
                          echo "${name} bootstrap: missing or malformed asset metadata" >&2
                          exit 1
                        }

                        echo "${name} bootstrap: installing $tag" >&2
                        archive="$tmpdir/$asset_name"
                        curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 "$expected_url" -o "$archive" || {
                          echo "${name} bootstrap: release download failed" >&2
                          exit 1
                        }
                        actual_digest=$(sha256sum "$archive" | awk '{ print $1 }')
                        if [ "$actual_digest" != "$expected_digest" ]; then
                          echo "${name} bootstrap: sha256 mismatch for $asset_name" >&2
                          exit 1
                        fi

          ${lib.optionalString (archiveMember != null) ''
            if ! tar -tzf "$archive" > "$tmpdir/members" \
              || ! awk -v root=${lib.escapeShellArg root} -v member=${lib.escapeShellArg archiveMember} '
                $0 !~ ("^" root "(/|$)") { valid = 0 }
                {
                  parts = split($0, component, "/")
                  for (i = 1; i <= parts; i++) {
                    if (component[i] == "..") valid = 0
                  }
                }
                $0 == member { count++ }
                END { exit !(valid != 0 && count == 1) }
              ' valid=1 "$tmpdir/members" \
              || ! tar -tvzf "$archive" | awk '
                substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { valid = 0 }
                END { exit !(valid != 0) }
              ' valid=1; then
              echo "${name} bootstrap: unexpected or unsafe archive layout" >&2
              exit 1
            fi

            mkdir "$tmpdir/extract"
            tar --extract --gzip --file "$archive" --directory "$tmpdir/extract" \
              --no-same-owner --no-same-permissions || {
              echo "${name} bootstrap: archive extraction failed" >&2
              exit 1
            }
            extracted_bin="$tmpdir/extract/${archiveMember}"
            if [ ! -f "$extracted_bin" ] || [ -L "$extracted_bin" ] || [ ! -x "$extracted_bin" ]; then
              echo "${name} bootstrap: archive lacks regular executable ${archiveMember}" >&2
              exit 1
            fi
          ''}
          ${lib.optionalString (archiveMember == null) ''
            extracted_bin="$archive"
            if [ ! -f "$extracted_bin" ] || [ -L "$extracted_bin" ] || [ ! -s "$extracted_bin" ]; then
              echo "${name} bootstrap: download is not a regular non-empty file" >&2
              exit 1
            fi
          ''}

                        if [ ! -x "$target" ]; then
                          new_bin=$(mktemp "$install_dir/.${name}.new.XXXXXX")
                          install -m 755 "$extracted_bin" "$new_bin"
                          mv -f "$new_bin" "$target"
                          new_bin=""
                        fi

          ${lib.optionalString installNativeAssets ''
            extracted_man="$tmpdir/extract/${root}/man/man1/${name}.1"
            if [ ! -f "$extracted_man" ] || [ -L "$extracted_man" ]; then
              echo "${name} bootstrap: archive lacks regular man/man1/${name}.1" >&2
              exit 1
            fi
            man_dir=$(dirname "$man_path")
            if [ -L "$man_dir" ] || { [ -e "$man_dir" ] && [ ! -d "$man_dir" ]; }; then
              echo "${name} bootstrap: unsafe man directory $man_dir" >&2
              exit 1
            fi
            mkdir -p "$man_dir"
            asset_tmp=$(mktemp "$man_dir/.${name}.1.new.XXXXXX")
            install -m 644 "$extracted_man" "$asset_tmp"
            mv -f "$asset_tmp" "$man_path"
            asset_tmp=""

            extracted_fish="$tmpdir/extract/${root}/share/fish/vendor_conf.d/${name}-activate.fish"
            if [ -f "$extracted_fish" ] && [ ! -L "$extracted_fish" ]; then
              fish_dir="$data_home/fish/vendor_conf.d"
              if [ -L "$fish_dir" ] || { [ -e "$fish_dir" ] && [ ! -d "$fish_dir" ]; }; then
                echo "${name} bootstrap: unsafe fish vendor directory $fish_dir" >&2
                exit 1
              fi
              mkdir -p "$fish_dir"
              asset_tmp=$(mktemp "$fish_dir/.${name}.new.XXXXXX")
              install -m 644 "$extracted_fish" "$asset_tmp"
              mv -f "$asset_tmp" "$fish_dir/${name}-activate.fish"
              asset_tmp=""
            fi

            asset_tmp=$(mktemp "$lock_dir/.${name}.assets.XXXXXX")
            printf '%s\n' "$tag" > "$asset_tmp"
            mv -f "$asset_tmp" "$assets_stamp"
            asset_tmp=""
            rm -f "$assets_retry"
          ''}
                        rm -rf "$tmpdir"
                        tmpdir=""
                        trap - EXIT HUP INT TERM
                      fi
                      flock -u 9
                      exec 9>&-
                    )
                    if ${archiveNeeded}; then
          ${
            if installNativeAssets then
              ''
                if [ ! -x "$target" ]; then
                  sync_archive
                else
                  retry_after=0
                  if [ -f "$assets_retry" ] && [ ! -L "$assets_retry" ] && [ ! "$target" -nt "$assets_retry" ]; then
                    saved_retry=$(cat "$assets_retry" 2>/dev/null || true)
                    if [[ "$saved_retry" =~ ^[0-9]+$ ]]; then
                      retry_after=$saved_retry
                    fi
                  fi
                  if [ "$(date +%s)" -ge "$retry_after" ]; then
                    set +e
                    sync_archive
                    sync_status=$?
                    set -e
                    if [ "$sync_status" -ne 0 ]; then
                      # Retry state is optional and must not block an installed binary.
                      if [ -d "$lock_dir" ] && [ ! -L "$lock_dir" ]; then
                        retry_tmp=""
                        if ! retry_tmp=$(mktemp "$lock_dir/.${name}.retry.XXXXXX") \
                          || ! printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$retry_tmp" \
                          || ! mv -f "$retry_tmp" "$assets_retry"; then
                          [ -z "$retry_tmp" ] || rm -f "$retry_tmp" || true
                        fi
                      fi
                      echo "${name} bootstrap: native asset refresh failed; using installed binary" >&2
                    fi
                  fi
                fi
              ''
            else
              "sync_archive"
          }
                    fi

          ${lib.optionalString (generatedAssets != [ ]) ''
              generate_asset() {
                local relative_path="$1"
                local generated_path generated_dir generated_tmp
                shift
                generated_path="$data_home/$relative_path"
                generated_dir=$(dirname "$generated_path")
                if [ -L "$generated_dir" ] || { [ -e "$generated_dir" ] && [ ! -d "$generated_dir" ]; }; then
                  echo "${name} bootstrap: unsafe generated asset directory $generated_dir" >&2
                  return
                fi
                if [ -L "$generated_path" ] || { [ -e "$generated_path" ] && [ ! -f "$generated_path" ]; }; then
                  echo "${name} bootstrap: unsafe generated asset path $generated_path" >&2
                  return
                fi
                if [ ! -f "$generated_path" ] || [ "$target" -nt "$generated_path" ]; then
                  mkdir -p "$generated_dir"
                  generated_tmp=$(mktemp "$generated_dir/.${name}.generated.XXXXXX")
                  if "$target" "$@" > "$generated_tmp" 2>/dev/null && [ -s "$generated_tmp" ]; then
                    mv -f "$generated_tmp" "$generated_path"
                  else
                    rm -f "$generated_tmp"
                    echo "${name} bootstrap: failed to generate $relative_path" >&2
                  fi
                fi
              }
            ${lib.concatMapStringsSep "\n" (
              asset:
              "            generate_asset ${lib.escapeShellArg asset.path} ${lib.escapeShellArgs asset.args}"
            ) generatedAssets}
          ''}
                    exec -a "$(basename "$0")" "$target" "$@"
        '';
      };
    in
    wrapper;
in
{
  mise = mkRuntimeStub {
    name = "mise";
    repo = "jdx/mise";
    archiveMember = "mise/bin/mise";
    generatedAssets = [
      {
        path = "zsh/site-functions/_mise";
        args = [
          "completion"
          "zsh"
        ];
      }
    ];
    installNativeAssets = true;
    arches = {
      "Darwin/arm64" = "macos-arm64";
      "Darwin/x86_64" = "macos-x64";
      "Linux/aarch64" = "linux-arm64-musl";
      "Linux/arm64" = "linux-arm64-musl";
      "Linux/x86_64" = "linux-x64-musl";
    };
  };

  topgrade = mkRuntimeStub {
    name = "topgrade";
    repo = "topgrade-rs/topgrade";
    archiveMember = "topgrade";
    generatedAssets = [
      {
        path = "bash-completion/completions/topgrade.bash";
        args = [
          "--gen-completion"
          "bash"
        ];
      }
      {
        path = "fish/vendor_completions.d/topgrade.fish";
        args = [
          "--gen-completion"
          "fish"
        ];
      }
      {
        path = "zsh/site-functions/_topgrade";
        args = [
          "--gen-completion"
          "zsh"
        ];
      }
      {
        path = "man/man1/topgrade.1";
        args = [ "--gen-manpage" ];
      }
    ];
    arches = {
      "Darwin/arm64" = "aarch64-apple-darwin";
      "Darwin/x86_64" = "x86_64-apple-darwin";
      "Linux/aarch64" = "aarch64-unknown-linux-musl";
      "Linux/arm64" = "aarch64-unknown-linux-musl";
      "Linux/x86_64" = "x86_64-unknown-linux-musl";
    };
  };

  herdr = mkRuntimeStub {
    name = "herdr";
    repo = "herdrdev/herdr";
    assetName = "herdr-$arch";
    generatedAssets = [
      {
        path = "bash-completion/completions/herdr.bash";
        args = [
          "completion"
          "bash"
        ];
      }
      {
        path = "fish/vendor_completions.d/herdr.fish";
        args = [
          "completion"
          "fish"
        ];
      }
      {
        path = "zsh/site-functions/_herdr";
        args = [
          "completion"
          "zsh"
        ];
      }
      {
        path = "herdr/skills/herdr/SKILL.md";
        args = [ "--skill" ];
      }
    ];
    installDir = ".local/bin";
    arches = {
      "Darwin/arm64" = "macos-aarch64";
      "Darwin/x86_64" = "macos-x86_64";
      "Linux/aarch64" = "linux-aarch64";
      "Linux/arm64" = "linux-aarch64";
      "Linux/x86_64" = "linux-x86_64";
    };
  };
}
