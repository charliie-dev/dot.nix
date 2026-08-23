#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  require_home_config
  TEST_ROOT=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "runtime binary updaters are not Home Manager activation entries" {
  generation=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".activationPackage")

  run grep -E 'upgradeMise|upgradeTopgrade' "$generation/activate"
  [ "$status" -ne 0 ]
}

@test "mise stub does not depend on the packaged mise build" {
  package_drv=$(nix eval --raw --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.mise.package.drvPath")

  run nix-store --query --requisites "$package_drv"
  [ "$status" -eq 0 ]
  ! grep -Eq '/[^/]+-mise-[0-9][^/]*\.drv$' <<<"$output"
}

@test "native manual directory is on MANPATH" {
  run nix eval --json --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.home.sessionSearchVariables.MANPATH"
  [ "$status" -eq 0 ]
  jq -e --arg path "$HOME/.local/share/man" 'index($path) != null' <<<"$output" >/dev/null
}

@test "mise stub installs native completion manual and shared shell assets" {
  package=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.mise.package")
  home="$TEST_ROOT/home"
  data="$home/.local/share"
  state="$home/.local/state"
  payload="$TEST_ROOT/payload/mise"
  archive="$TEST_ROOT/mise.tar.gz"
  mkdir -p "$payload/bin" "$payload/man/man1" "$payload/share/fish/vendor_conf.d"
  cat > "$payload/bin/mise" <<'SH'
#!/bin/sh
case "${1-}" in
  --version) printf '1.2.3 fixture\n' ;;
  completion) printf '#compdef mise\n_native_mise_completion\n' ;;
  *) printf 'native mise: %s\n' "$*" ;;
esac
SH
  chmod +x "$payload/bin/mise"
  printf 'fixture man page\n' > "$payload/man/man1/mise.1"
  printf 'fixture fish activation\n' > "$payload/share/fish/vendor_conf.d/mise-activate.fish"
  COPYFILE_DISABLE=1 tar -czf "$archive" -C "$TEST_ROOT/payload" mise

  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) arch=macos-arm64 ;;
    Darwin/x86_64) arch=macos-x64 ;;
    Linux/aarch64 | Linux/arm64) arch=linux-arm64-musl ;;
    Linux/x86_64) arch=linux-x64-musl ;;
    *) return 1 ;;
  esac
  tag=v1.2.3
  asset_name="mise-$tag-$arch.tar.gz"
  asset_url="https://github.com/jdx/mise/releases/download/$tag/$asset_name"
  digest=$(nix hash file --type sha256 --base16 "$archive")
  release_json="$TEST_ROOT/release.json"
  jq -n \
    --arg tag "$tag" \
    --arg name "$asset_name" \
    --arg url "$asset_url" \
    --arg digest "sha256:$digest" \
    '{tag_name: $tag, assets: [{name: $name, browser_download_url: $url, digest: $digest}]}' \
    > "$release_json"

  export FIXTURE_ARCHIVE="$archive" FIXTURE_RELEASE_JSON="$release_json"
  curl() {
    local output=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then
        output=$2
        shift 2
      else
        shift
      fi
    done
    if [[ "$output" = */release.json ]]; then
      cp "$FIXTURE_RELEASE_JSON" "$output"
      printf 200
    else
      cp "$FIXTURE_ARCHIVE" "$output"
    fi
  }
  export -f curl

  stdout_file="$TEST_ROOT/stdout"
  stderr_file="$TEST_ROOT/stderr"
  run bash -c 'HOME="$1" XDG_DATA_HOME="$2" XDG_STATE_HOME="$3" "$4/bin/mise" doctor > "$5" 2> "$6"' \
    _ "$home" "$data" "$state" "$package" "$stdout_file" "$stderr_file"
  [ "$status" -eq 0 ]
  [ "$(cat "$stdout_file")" = "native mise: doctor" ]
  grep -q '^mise bootstrap: installing v1.2.3$' "$stderr_file"
  grep -q '^_native_mise_completion$' "$data/zsh/site-functions/_mise"
  grep -q '^fixture man page$' "$data/man/man1/mise.1"
  grep -q '^fixture fish activation$' "$data/fish/vendor_conf.d/mise-activate.fish"
  grep -q '^v1.2.3$' "$state/home-manager/mise-assets-version"
}

@test "existing native mise remains usable when asset refresh is offline" {
  package=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.mise.package")
  home="$TEST_ROOT/home"
  data="$home/.local/share"
  state="$home/.local/state"
  mkdir -p "$data/mise/bin"
  cat > "$data/mise/bin/mise" <<'SH'
#!/bin/sh
case "${1-}" in
  --version) printf '1.2.3 fixture\n' ;;
  completion) printf '#compdef mise\n_native_mise_completion\n' ;;
  *) printf 'native mise: %s\n' "$*" ;;
esac
SH
  chmod +x "$data/mise/bin/mise"
  export CURL_CALLS="$TEST_ROOT/curl-calls"
  curl() {
    printf x >> "$CURL_CALLS"
    return 1
  }
  export -f curl

  run env HOME="$home" XDG_DATA_HOME="$data" XDG_STATE_HOME="$state" "$package/bin/mise" doctor
  [ "$status" -eq 0 ]
  [[ "$output" = *"native mise: doctor"* ]]
  grep -q '^_native_mise_completion$' "$data/zsh/site-functions/_mise"

  run env HOME="$home" XDG_DATA_HOME="$data" XDG_STATE_HOME="$state" "$package/bin/mise" doctor
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$CURL_CALLS" | tr -d ' ')" -eq 1 ]
}

@test "current Zsh session registers a newly generated mise completion" {
  run nix eval --raw --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.zsh.initContent"
  [ "$status" -eq 0 ]
  [[ "$output" = *"compdef _mise mise"* ]]
}

@test "mise stub refreshes Zsh completion from the native binary" {
  package=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.mise.package")
  home="$TEST_ROOT/home"
  data="$home/.local/share"
  state="$home/.local/state"
  mkdir -p "$data/mise/bin" "$data/man/man1" "$state/home-manager"
  cat > "$data/mise/bin/mise" <<'SH'
#!/bin/sh
if [ "${1-}" = completion ] && [ "${2-}" = zsh ]; then
  printf '#compdef mise\n_native_mise_completion\n'
  exit 0
fi
printf 'native mise: %s\n' "$*"
SH
  chmod +x "$data/mise/bin/mise"
  printf 'fixture man page\n' > "$data/man/man1/mise.1"
  printf 'v0.0.0\n' > "$state/home-manager/mise-assets-version"

  run env HOME="$home" XDG_DATA_HOME="$data" XDG_STATE_HOME="$state" "$package/bin/mise" doctor
  [ "$status" -eq 0 ]
  [ "$output" = "native mise: doctor" ]
  grep -q '^_native_mise_completion$' "$data/zsh/site-functions/_mise"
}
