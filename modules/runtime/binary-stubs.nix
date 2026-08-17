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
      member,
      arches,
    }:
    let
      upstream = prev.${name};
      root = lib.head (lib.splitString "/" member);
      archCases = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (platform: arch: "          ${platform}) arch=${arch} ;;") arches
      );
      wrapper = prev.writeShellApplication {
        inherit name runtimeInputs;
        text = ''
                    target="$HOME/.local/share/${name}/bin/${name}"
                    if [ ! -x "$target" ]; then
                      umask 077
                      case "$(uname -s)/$(uname -m)" in
          ${archCases}
                        *)
                          echo "${name} bootstrap: unsupported $(uname -ms)" >&2
                          exit 1
                          ;;
                      esac

                      install_dir="$HOME/.local/share/${name}/bin"
                      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
                      lock_dir="$state_home/home-manager/locks"
                      lock_path="$lock_dir/${name}-bootstrap.lock"

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
                      [ -x "$target" ] || {
                        tmpdir=$(mktemp -d)
                        new_bin=""
                        trap 'rm -rf "$tmpdir"; [ -z "$new_bin" ] || rm -f "$new_bin"' EXIT HUP INT TERM

                        repo=${repo}
                        api_url="https://api.github.com/repos/$repo/releases/latest"
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

                        asset_name="${name}-$tag-$arch.tar.gz"
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

                        echo "${name} bootstrap: installing $tag"
                        archive="$tmpdir/$asset_name"
                        curl -fsSL --max-time 60 "$expected_url" -o "$archive" || {
                          echo "${name} bootstrap: release download failed" >&2
                          exit 1
                        }
                        actual_digest=$(sha256sum "$archive" | awk '{ print $1 }')
                        if [ "$actual_digest" != "$expected_digest" ]; then
                          echo "${name} bootstrap: sha256 mismatch for $asset_name" >&2
                          exit 1
                        fi

                        if ! tar -tzf "$archive" > "$tmpdir/members" \
                          || ! awk -v root=${lib.escapeShellArg root} -v member=${lib.escapeShellArg member} '
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
                        extracted_bin="$tmpdir/extract/${member}"
                        if [ ! -f "$extracted_bin" ] || [ -L "$extracted_bin" ] || [ ! -x "$extracted_bin" ]; then
                          echo "${name} bootstrap: archive lacks regular executable ${member}" >&2
                          exit 1
                        fi

                        new_bin=$(mktemp "$install_dir/.${name}.new.XXXXXX")
                        install -m 755 "$extracted_bin" "$new_bin"
                        mv -f "$new_bin" "$target"
                        new_bin=""
                      }
                      flock -u 9
                      exec 9>&-
                    fi

                    exec -a "$(basename "$0")" "$target" "$@"
        '';
      };
    in
    prev.symlinkJoin {
      inherit name;
      paths = [ upstream ];
      postBuild = ''
        rm -f "$out/bin/${name}"
        ln -s ${lib.getExe wrapper} "$out/bin/${name}"
      '';
      meta.mainProgram = name;
      passthru = { inherit upstream; };
    };
in
{
  mise = mkRuntimeStub {
    name = "mise";
    repo = "jdx/mise";
    member = "mise/bin/mise";
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
    member = "topgrade";
    arches = {
      "Darwin/arm64" = "aarch64-apple-darwin";
      "Darwin/x86_64" = "x86_64-apple-darwin";
      "Linux/aarch64" = "aarch64-unknown-linux-musl";
      "Linux/arm64" = "aarch64-unknown-linux-musl";
      "Linux/x86_64" = "x86_64-unknown-linux-musl";
    };
  };
}
