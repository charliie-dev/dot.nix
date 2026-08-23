#!/usr/bin/env bats

load "../lib/home-config"

setup_file() {
  require_home_config
  GENERATED_ZSHRC=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.home.file.\".config/zsh/.zshrc\".source")
  TOPGRADE_PACKAGE=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; system = f.homeConfigurations.\"$(home_config_name)\".pkgs.stdenv.hostPlatform.system; in (builtins.getAttr system f.inputs.nixpkgs.legacyPackages).topgrade")
  ZSH_PACKAGE=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.zsh.package")
  HOME_IS_DARWIN=$(nix eval --impure --json --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".pkgs.stdenv.hostPlatform.isDarwin")
  TOPGRADE_BIN="$TOPGRADE_PACKAGE/bin/topgrade"
  ZSH_BIN="$ZSH_PACKAGE/bin/zsh"
  GIT_GUARD_DIR="$BATS_FILE_TMPDIR/git-guard-bin"
  mkdir -p "$GIT_GUARD_DIR"
  cat > "$GIT_GUARD_DIR/git" <<'EOF'
#!/bin/sh
if [ "$#" -eq 5 ] && [ "$1" = -C ] && [ "$3" = config ] \
  && [ "$4" = --get ] && [ "$5" = antidote.pin ] \
  && [ -n "$ANTIDOTE_TEST_GIT_ROOT" ]; then
  case "$2" in
    "$ANTIDOTE_TEST_GIT_ROOT"/*)
      printf 'allowed-read:%s\n' "$*" >> "${GIT_GUARD_LOG:?}"
      exit 1
      ;;
  esac
fi
printf 'blocked:%s\n' "$*" >> "${GIT_GUARD_LOG:?}"
exit 97
EOF
  chmod 0700 "$GIT_GUARD_DIR/git"
  LOADER_FIXTURE_PATH="$GIT_GUARD_DIR:${ZSH_BIN%/bin/zsh}/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  GIT_CONFIG_NOSYSTEM=1
  GIT_CONFIG_GLOBAL=/dev/null
  GIT_OPTIONAL_LOCKS=0
  export GENERATED_ZSHRC TOPGRADE_BIN ZSH_BIN HOME_IS_DARWIN
  export GIT_GUARD_DIR LOADER_FIXTURE_PATH
  export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_OPTIONAL_LOCKS
}

extract_loader() {
  local zshrc="$1"
  local output="$2"

  sed -n '/^## home-manager\/antidote begin$/,/^## home-manager\/antidote end$/p' \
    "$zshrc" > "$output"
}

seed_plugins() {
  local root="$1"
  local repo path name

  while read -r repo path; do
    [ -n "$repo" ] || continue
    name="${path:+${path##*/}}"
    name="${name:-${repo##*/}}"
    mkdir -p "$root/$repo${path:+/$path}"
    cat > "$root/$repo${path:+/$path}/$name.plugin.zsh" <<EOF
print -r -- '$repo${path:+/$path}' >> "\$ANTIDOTE_TEST_LOG"
EOF
  done <<'EOF'
QuarticCat/zsh-smartcache
Aloxaf/fzf-tab
zsh-users/zsh-autosuggestions
zsh-users/zsh-history-substring-search
MichaelAquilina/zsh-you-should-use
mattmc3/zephyr plugins/homebrew
mattmc3/zephyr plugins/macos
EOF

  cat >> "$root/QuarticCat/zsh-smartcache/zsh-smartcache.plugin.zsh" <<'EOF'
smartcache() { return 0 }
EOF
  mkdir -p "$root/romkatv/zsh-defer"
  cat > "$root/romkatv/zsh-defer/zsh-defer.plugin.zsh" <<'EOF'
print -r -- 'romkatv/zsh-defer' >> "$ANTIDOTE_TEST_LOG"
zsh-defer() { "$@" }
EOF
}

write_expected_plugin_log() {
  local output="$1"

  cat > "$output" <<'EOF'
QuarticCat/zsh-smartcache
romkatv/zsh-defer
Aloxaf/fzf-tab
zsh-users/zsh-autosuggestions
zsh-users/zsh-history-substring-search
MichaelAquilina/zsh-you-should-use
EOF
  if [ "$HOME_IS_DARWIN" = true ]; then
    cat >> "$output" <<'EOF'
mattmc3/zephyr/plugins/homebrew
mattmc3/zephyr/plugins/macos
EOF
  fi
}

run_loader() {
  local loader="$1"
  local root="$2"
  local home="$3"
  local log="$4"
  local git_log="${5:-$BATS_TEST_TMPDIR/git-guard.log}"

  mkdir -p "$home"
  env -i \
    HOME="$home" \
    XDG_CACHE_HOME="$home/xdg-cache" \
    ANTIDOTE_HOME="$root" \
    ANTIDOTE_TEST_GIT_ROOT="$root" \
    ANTIDOTE_TEST_LOG="$log" \
    ANTIDOTE_TEST_FOREIGN_PATH="${ANTIDOTE_TEST_FOREIGN_PATH:-}" \
    GIT_CONFIG_NOSYSTEM="$GIT_CONFIG_NOSYSTEM" \
    GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
    GIT_OPTIONAL_LOCKS="$GIT_OPTIONAL_LOCKS" \
    GIT_GUARD_LOG="$git_log" \
    PATH="$LOADER_FIXTURE_PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" \
    "$ZSH_BIN" -f "$loader"
}

run_loader_with_xdg_home() {
  local loader="$1"
  local root="$2"
  local home="$3"
  local xdg_cache="$4"
  local log="$5"
  local git_log="${6:-$BATS_TEST_TMPDIR/git-guard.log}"

  mkdir -p "$home" "$xdg_cache"
  env -i \
    HOME="$home" \
    XDG_CACHE_HOME="$xdg_cache" \
    ANTIDOTE_TEST_GIT_ROOT="$root" \
    ANTIDOTE_TEST_LOG="$log" \
    GIT_CONFIG_NOSYSTEM="$GIT_CONFIG_NOSYSTEM" \
    GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
    GIT_OPTIONAL_LOCKS="$GIT_OPTIONAL_LOCKS" \
    GIT_GUARD_LOG="$git_log" \
    PATH="$LOADER_FIXTURE_PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" \
    "$ZSH_BIN" -f "$loader"
}

assert_no_network_git() {
  local log="$1"
  local unexpected

  [ -f "$log" ] || return 0
  unexpected=$(grep -Ev '^allowed-read:-C .+ config --get antidote\.pin$' "$log" || true)
  [ -z "$unexpected" ]
}

zstat_mode() {
  "$ZSH_BIN" -fc '
    zmodload zsh/stat
    local -A info
    zstat -H info -- "$1"
    printf "%o\n" $(( info[mode] & 8#777 ))
  ' zsh "$1"
}

static_name() {
  grep -Eo 'home-manager-[0-9a-f]+\.zsh' "$1" | head -n 1
}

make_unsafe_path() {
  local kind="$1"
  local path="$2"
  local sentinel="$3"

  case "$kind" in
    symlink)
      printf 'sentinel\n' > "$sentinel"
      ln -s "$sentinel" "$path"
      ;;
    nonregular)
      mkdir "$path"
      ;;
    group-write)
      printf 'unsafe\n' > "$path"
      chmod 0620 "$path"
      ;;
    world-write)
      printf 'unsafe\n' > "$path"
      chmod 0602 "$path"
      ;;
    hardlink)
      printf 'unsafe\n' > "$sentinel"
      ln "$sentinel" "$path"
      ;;
    foreign)
      printf 'unsafe\n' > "$path"
      chmod 0600 "$path"
      ;;
  esac
}

loader_with_foreign_uid() {
  local loader="$1"
  local output="$2"

  cat > "$output" <<'EOF'
zmodload zsh/stat
zstat() {
  builtin zstat "$@"
  local result=$?
  if (( result == 0 )) && [[ "${@[-1]}" == "$ANTIDOTE_TEST_FOREIGN_PATH" ]]; then
    _hm_antidote_info[uid]=$(( EUID + 1 ))
  fi
  return $result
}
EOF
  cat "$loader" >> "$output"
}

@test "generated zshrc has one pinned order-550 loader without shared tmp state" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  extract_loader "$zshrc" "$loader"

  if grep -Fq '/tmp/tmp_hm_zsh_plugins' "$zshrc"; then
    echo "generated zshrc still uses shared /tmp/tmp_hm_zsh_plugins" >&2
    false
  fi

  begin_count=$(grep -c '^## home-manager/antidote begin$' "$zshrc" || true)
  end_count=$(grep -c '^## home-manager/antidote end$' "$zshrc" || true)
  load_count=$(grep -Ec '^[[:space:]]*antidote load ' "$zshrc" || true)
  [ "$begin_count" -eq 1 ]
  [ "$end_count" -eq 1 ]
  [ "$load_count" -eq 1 ]

  grep -Eq '^source /nix/store/[^ ]+-antidote-[^/]+/share/antidote/antidote\.zsh$' "$loader"
  grep -Fxq "zstyle ':antidote:bundle' use-friendly-names 'yes'" "$loader"
  grep -Fxq 'zstyle '\'':antidote:home'\'' dir "${XDG_CACHE_HOME:-$HOME/.cache}/antidote"' "$loader"
  grep -Fq '_hm_antidote_home="$(antidote home)"' "$loader"
  ! grep -Fq '/Users/charles' "$loader"
  grep -Fq 'home-manager-' "$loader"
  grep -Fq "zstyle ':antidote:static' file \"\$_hm_antidote_static\"" "$loader"
  grep -Fq 'antidote load "$_hm_antidote_bundle" "$_hm_antidote_static"' "$loader"
  grep -Fq 'zmodload zsh/stat' "$loader"
  grep -Fq 'zstat -H _hm_antidote_info' "$loader"
  grep -Fq '_hm_antidote_info[uid] == EUID' "$loader"
  grep -Fq '_hm_antidote_info[nlink] == 1' "$loader"
  grep -Fq '_hm_antidote_sidecar="$_hm_antidote_static.zwc"' "$loader"
  ! grep -Eq '(^|[^[:alnum:]_])eval([[:space:]]|$)' "$loader"
}

@test "rendered immutable bundle preserves exact plugin bytes and order" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  expected="$BATS_TEST_TMPDIR/expected-bundle"
  extract_loader "$zshrc" "$loader"

  bundle=$(sed -n 's/^_hm_antidote_bundle=//p' "$loader")
  bundle="${bundle#\'}"
  bundle="${bundle%\'}"
  [ -f "$bundle" ]

  cat > "$expected" <<'EOF'
QuarticCat/zsh-smartcache
Aloxaf/fzf-tab kind:defer
zsh-users/zsh-autosuggestions kind:defer
zsh-users/zsh-history-substring-search kind:defer
MichaelAquilina/zsh-you-should-use kind:defer
EOF
  if [ "$HOME_IS_DARWIN" = true ]; then
    cat >> "$expected" <<'EOF'
mattmc3/zephyr path:plugins/homebrew
mattmc3/zephyr path:plugins/macos
EOF
  fi

  cmp "$expected" "$bundle"
}

@test "bundle helper accepts only canonical source-controlled specs" {
  check="$BATS_TEST_TMPDIR/helper-check.nix"
  cat > "$check" <<EOF
let
  render = import $REPO/modules/apps/zsh/antidote-bundle.nix;
  fails = specs: !(builtins.tryEval (builtins.deepSeq (render specs) true)).success;
  invalid = [
    [ { repo = "owner"; } ]
    [ { repo = "owner/repo/extra"; } ]
    [ { repo = "-owner/repo"; } ]
    [ { repo = "owner--name/repo"; } ]
    [ { repo = "owner/."; } ]
    [ { repo = "owner/.."; } ]
    [ { repo = "owner/repo;touch"; } ]
    [ { repo = "owner/repo\nnext"; } ]
    [ { repo = "owner/repo\rnext"; } ]
    [ { repo = builtins.fromJSON ''"owner/repo\\u0001"''; } ]
    [ { repo = "owner/repo"; kind = "clone"; } ]
    [ { repo = "owner/repo"; kind = true; } ]
    [ { repo = "owner/repo"; path = "/absolute"; } ]
    [ { repo = "owner/repo"; path = "../traversal"; } ]
    [ { repo = "owner/repo"; path = "a/./b"; } ]
    [ { repo = "owner/repo"; path = "a//b"; } ]
    [ { repo = "owner/repo"; path = "has space"; } ]
    [ { repo = "owner/repo"; path = "meta/\$(touch)"; } ]
    [ { repo = "owner/repo"; path = "meta;command"; } ]
    [ { repo = "owner/repo"; path = "line\nnext"; } ]
    [ { repo = "owner/repo"; path = "tab\there"; } ]
    [ { repo = "owner/repo"; path = builtins.fromJSON ''"part/\\u0001"''; } ]
    [ { repo = "owner/repo"; path = 1; } ]
    [ { repo = "owner/repo"; branch = "main"; } ]
    [ { repo = "owner/repo"; } { repo = "owner/repo"; } ]
    [ "owner/repo" ]
    "owner/repo"
  ];
in {
  valid = render [
    { repo = "owner/repo"; path = "plugins/example"; kind = "defer"; }
  ] == [ "owner/repo kind:defer path:plugins/example" ];
  invalid = builtins.all fails invalid;
}
EOF

  run nix eval --json --file "$check"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.valid')" = true ]
  [ "$(printf '%s' "$output" | jq -r '.invalid')" = true ]
}

@test "antidote remains in home packages and the built profile" {
  packages="$BATS_TEST_TMPDIR/packages.json"
  nix eval --impure --json --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.home.packages" \
    > "$packages"
  [ "$(jq '[.[] | select(contains("-antidote-"))] | length' "$packages")" -eq 1 ]

  profile=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.home.path")
  [ -f "$profile/share/antidote/antidote.zsh" ]
}

@test "loader fixtures put a fail-closed Git guard first" {
  [ -x "$GIT_GUARD_DIR/git" ]
  [[ "$LOADER_FIXTURE_PATH" == "$GIT_GUARD_DIR:"* ]]
  [ "$GIT_CONFIG_NOSYSTEM" = 1 ]
  [ "$GIT_CONFIG_GLOBAL" = /dev/null ]
  [ "$GIT_OPTIONAL_LOCKS" = 0 ]

  run env -i PATH="$LOADER_FIXTURE_PATH" "$ZSH_BIN" -fc 'print -r -- $commands[git]'
  [ "$status" -eq 0 ]
  [ "$output" = "$GIT_GUARD_DIR/git" ]

  probe_log="$BATS_TEST_TMPDIR/git-probe.log"
  run env -i GIT_GUARD_LOG="$probe_log" PATH="$LOADER_FIXTURE_PATH" git fetch
  [ "$status" -eq 97 ]
  [ "$(cat "$probe_log")" = blocked:fetch ]
}

@test "unset ANTIDOTE_HOME uses runtime XDG cache and exact plugins" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  home="$BATS_TEST_TMPDIR/home"
  xdg_cache="$BATS_TEST_TMPDIR/xdg-cache"
  root="$xdg_cache/antidote"
  log="$BATS_TEST_TMPDIR/loaded"
  expected_log="$BATS_TEST_TMPDIR/expected-plugin-log"
  git_log="$BATS_TEST_TMPDIR/git.log"
  extract_loader "$zshrc" "$loader"
  cat >> "$loader" <<'EOF'
print -r -- "antidote-home=$(antidote home)"
EOF
  seed_plugins "$root"
  write_expected_plugin_log "$expected_log"

  run run_loader_with_xdg_home "$loader" "$root" "$home" "$xdg_cache" "$log" "$git_log"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Fxq "antidote-home=$root"
  errors=$(printf '%s\n' "$output" | grep -Ei 'not found|no such file|smartcache|zsh-defer' || true)
  [ -z "$errors" ]
  static_dir="$root/home-manager"
  static=$(find "$static_dir" -maxdepth 1 -type f -name 'home-manager-*.zsh' -print)
  [ -n "$static" ]
  [ ! -L "$static" ]
  [ "$(zstat_mode "$static_dir")" = 700 ]
  cmp "$expected_log" "$log"
  assert_no_network_git "$git_log"
}

@test "explicit ANTIDOTE_HOME overrides runtime XDG home and isolates static files" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  expected_log="$BATS_TEST_TMPDIR/expected-plugin-log"
  extract_loader "$zshrc" "$loader"
  write_expected_plugin_log "$expected_log"

  for id in one two; do
    root="$BATS_TEST_TMPDIR/antidote-$id"
    home="$BATS_TEST_TMPDIR/home-$id"
    log="$BATS_TEST_TMPDIR/loaded-$id"
    seed_plugins "$root"
    run run_loader "$loader" "$root" "$home" "$log"
    [ "$status" -eq 0 ]
    errors=$(printf '%s\n' "$output" | grep -Ei 'not found|no such file|smartcache|zsh-defer' || true)
    [ -z "$errors" ]
    static_dir="$root/home-manager"
    static=$(find "$static_dir" -maxdepth 1 -type f -name 'home-manager-*.zsh' -print)
    [ -n "$static" ]
    [ ! -L "$static" ]
    [ ! -e "$home/xdg-cache/antidote/home-manager" ]
    [ "$(zstat_mode "$static_dir")" = 700 ]
    [ -s "$log" ]
    cmp "$expected_log" "$log"
    printf '%s\n' "$static" >> "$BATS_TEST_TMPDIR/static-paths"
  done

  [ "$(sort -u "$BATS_TEST_TMPDIR/static-paths" | wc -l | tr -d ' ')" -eq 2 ]
  assert_no_network_git "$BATS_TEST_TMPDIR/git-guard.log"
}

@test "private child creation is idempotent and still validates unsafe state" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  root="$BATS_TEST_TMPDIR/antidote"
  child="$root/home-manager"
  home="$BATS_TEST_TMPDIR/home"
  log="$BATS_TEST_TMPDIR/loaded"
  git_log="$BATS_TEST_TMPDIR/git.log"
  extract_loader "$zshrc" "$loader"

  creation_count=$(grep -Ec '^[[:space:]]*/nix/store/[^ ]+-coreutils-[^/]+/bin/mkdir -p -m 0700 -- "\$_hm_antidote_static_dir" 2>/dev/null \|\| true$' "$loader" || true)
  [ "$creation_count" -eq 1 ]
  grep -Fq '! _hm_antidote_safe_dir "$_hm_antidote_static_dir" private' "$loader"

  seed_plugins "$root"
  mkdir "$child"
  chmod 0777 "$child"
  run run_loader "$loader" "$root" "$home" "$log" "$git_log"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Fq 'home-manager antidote: refusing unsafe static directory'
  [ ! -e "$log" ]
  assert_no_network_git "$git_log"
}

@test "unsafe antidote roots and dedicated children fail closed" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  extract_loader "$zshrc" "$loader"

  for kind in symlink group-write world-write foreign; do
    base="$BATS_TEST_TMPDIR/root-$kind"
    root="$base/antidote"
    home="$base/home"
    log="$base/loaded"
    git_log="$base/git.log"
    mkdir -p "$base"
    if [ "$kind" = symlink ]; then
      real_root="$base/real-antidote"
      seed_plugins "$real_root"
      ln -s "$real_root" "$root"
    else
      seed_plugins "$root"
      case "$kind" in
        group-write) chmod 0775 "$root" ;;
        world-write) chmod 0777 "$root" ;;
      esac
    fi

    selected_loader="$loader"
    if [ "$kind" = foreign ]; then
      selected_loader="$base/foreign-loader.zsh"
      loader_with_foreign_uid "$loader" "$selected_loader"
      ANTIDOTE_TEST_FOREIGN_PATH="$root"
    fi
    run run_loader "$selected_loader" "$root" "$home" "$log" "$git_log"
    unset ANTIDOTE_TEST_FOREIGN_PATH
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -Fq 'home-manager antidote: refusing unsafe antidote home'
    [ ! -e "$log" ]
    assert_no_network_git "$git_log"
  done

  for kind in symlink nonregular group-write world-write foreign; do
    base="$BATS_TEST_TMPDIR/child-$kind"
    root="$base/antidote"
    child="$root/home-manager"
    home="$base/home"
    log="$base/loaded"
    git_log="$base/git.log"
    seed_plugins "$root"
    case "$kind" in
      symlink)
        mkdir "$base/child-target"
        ln -s "$base/child-target" "$child"
        ;;
      nonregular)
        printf 'unsafe\n' > "$child"
        ;;
      group-write)
        mkdir -m 0775 "$child"
        ;;
      world-write)
        mkdir -m 0777 "$child"
        ;;
      foreign)
        mkdir -m 0700 "$child"
        ;;
    esac

    selected_loader="$loader"
    if [ "$kind" = foreign ]; then
      selected_loader="$base/foreign-loader.zsh"
      loader_with_foreign_uid "$loader" "$selected_loader"
      ANTIDOTE_TEST_FOREIGN_PATH="$child"
    fi
    run run_loader "$selected_loader" "$root" "$home" "$log" "$git_log"
    unset ANTIDOTE_TEST_FOREIGN_PATH
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -Fq 'home-manager antidote: refusing unsafe static directory'
    [ ! -e "$log" ]
    assert_no_network_git "$git_log"
  done
}

@test "unsafe static files and compiled sidecars fail closed" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  extract_loader "$zshrc" "$loader"
  name=$(static_name "$loader")
  [ -n "$name" ]

  for target_kind in static sidecar; do
    for unsafe_kind in symlink nonregular group-write world-write hardlink foreign; do
      base="$BATS_TEST_TMPDIR/$target_kind-$unsafe_kind"
      root="$base/antidote"
      child="$root/home-manager"
      home="$base/home"
      log="$base/loaded"
      git_log="$base/git.log"
      sentinel="$base/sentinel"
      mkdir -p "$child"
      chmod 0700 "$child"
      seed_plugins "$root"
      static="$child/$name"
      if [ "$target_kind" = sidecar ]; then
        target="$static.zwc"
        warning='home-manager antidote: refusing unsafe static sidecar'
      else
        target="$static"
        warning='home-manager antidote: refusing unsafe static file'
      fi
      make_unsafe_path "$unsafe_kind" "$target" "$sentinel"

      selected_loader="$loader"
      if [ "$unsafe_kind" = foreign ]; then
        selected_loader="$base/foreign-loader.zsh"
        loader_with_foreign_uid "$loader" "$selected_loader"
        ANTIDOTE_TEST_FOREIGN_PATH="$target"
      fi
      run run_loader "$selected_loader" "$root" "$home" "$log" "$git_log"
      unset ANTIDOTE_TEST_FOREIGN_PATH
      [ "$status" -eq 0 ]
      printf '%s\n' "$output" | grep -Fq "$warning"
      [ ! -e "$log" ]
      if [ "$unsafe_kind" = symlink ]; then
        [ "$(cat "$sentinel")" = sentinel ]
        [ -L "$target" ]
      fi
      assert_no_network_git "$git_log"
    done
  done
}

@test "concurrent shells leave one complete static file and no partial remnants" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  root="$BATS_TEST_TMPDIR/antidote-concurrent"
  home="$BATS_TEST_TMPDIR/home-concurrent"
  extract_loader "$zshrc" "$loader"
  seed_plugins "$root"
  mkdir -p "$home"

  run bash -c '
    env -i HOME="$1" ANTIDOTE_HOME="$2" ANTIDOTE_TEST_LOG="$3" \
      ANTIDOTE_TEST_GIT_ROOT="$2" \
      GIT_CONFIG_NOSYSTEM="$GIT_CONFIG_NOSYSTEM" GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
      GIT_OPTIONAL_LOCKS="$GIT_OPTIONAL_LOCKS" GIT_GUARD_LOG="$4/concurrent-git.log" \
      PATH="$LOADER_FIXTURE_PATH" TMPDIR="$4" "$ZSH_BIN" -f "$5" >"$4/one.out" 2>&1 &
    one=$!
    env -i HOME="$1" ANTIDOTE_HOME="$2" ANTIDOTE_TEST_LOG="$3" \
      ANTIDOTE_TEST_GIT_ROOT="$2" \
      GIT_CONFIG_NOSYSTEM="$GIT_CONFIG_NOSYSTEM" GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
      GIT_OPTIONAL_LOCKS="$GIT_OPTIONAL_LOCKS" GIT_GUARD_LOG="$4/concurrent-git.log" \
      PATH="$LOADER_FIXTURE_PATH" TMPDIR="$4" "$ZSH_BIN" -f "$5" >"$4/two.out" 2>&1 &
    two=$!
    wait "$one"; first=$?
    wait "$two"; second=$?
    cat "$4/one.out" "$4/two.out"
    [ "$first" -eq 0 ] && [ "$second" -eq 0 ]
  ' bash "$home" "$root" "$BATS_TEST_TMPDIR/concurrent-loaded" "$BATS_TEST_TMPDIR" "$loader"
  [ "$status" -eq 0 ]
  errors=$(printf '%s\n' "$output" | grep -Ei 'not found|no such file|smartcache|zsh-defer' || true)
  [ -z "$errors" ]
  child="$root/home-manager"
  [ "$(find "$child" -maxdepth 1 -type f -name 'home-manager-*.zsh' | wc -l | tr -d ' ')" -eq 1 ]
  [ -z "$(find "$child" -maxdepth 1 -name '.home-manager-*.new.*' -print)" ]
  [ "$(zstat_mode "$child")" = 700 ]
  assert_no_network_git "$BATS_TEST_TMPDIR/concurrent-git.log"
}

@test "hostile static symlink warns and neither changes sentinel nor sources plugins" {
  zshrc="$GENERATED_ZSHRC"
  loader="$BATS_TEST_TMPDIR/loader.zsh"
  root="$BATS_TEST_TMPDIR/antidote-hostile"
  home="$BATS_TEST_TMPDIR/home-hostile"
  log="$BATS_TEST_TMPDIR/hostile-loaded"
  sentinel="$BATS_TEST_TMPDIR/sentinel"
  extract_loader "$zshrc" "$loader"
  seed_plugins "$root"
  mkdir -p "$home" "$root/home-manager"
  chmod 0700 "$root/home-manager"

  static_name=$(static_name "$loader")
  [ -n "$static_name" ]
  static="$root/home-manager/$static_name"
  printf 'unchanged\n' > "$sentinel"
  ln -s "$sentinel" "$static"

  run run_loader "$loader" "$root" "$home" "$log"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Fqi 'refusing unsafe static file'
  [ "$(cat "$sentinel")" = unchanged ]
  [ -L "$static" ]
  [ ! -e "$log" ]
  assert_no_network_git "$BATS_TEST_TMPDIR/git-guard.log"
}

@test "topgrade fixture uses pinned Topgrade and configured Zsh" {
  [[ "$TOPGRADE_BIN" == /nix/store/*/bin/topgrade ]]
  [[ "$ZSH_BIN" == /nix/store/*/bin/zsh ]]
  [ -x "$TOPGRADE_BIN" ]
  [ -x "$ZSH_BIN" ]
  ambient_pattern=$(printf 'command -v %s' topgrade)
  skip_pattern=$(printf 'skip "%s is not installed"' topgrade)
  ! grep -Fq "$ambient_pattern" "$BATS_TEST_FILENAME"
  ! grep -Fq "$skip_pattern" "$BATS_TEST_FILENAME"
}

@test "isolated topgrade detects exactly one built-in antidote update" {
  zshrc="$GENERATED_ZSHRC"
  zdotdir="$BATS_TEST_TMPDIR/zdotdir"
  home="$BATS_TEST_TMPDIR/topgrade-home"
  root="$BATS_TEST_TMPDIR/topgrade-antidote"
  config="$BATS_TEST_TMPDIR/topgrade.toml"
  log="$BATS_TEST_TMPDIR/topgrade-loaded"
  mkdir -p "$zdotdir" "$home" "$home/.cache" "$home/.config" "$home/.local/share" "$home/.local/state"
  extract_loader "$zshrc" "$zdotdir/.zshrc"
  seed_plugins "$root"
  cat > "$config" <<'EOF'
[misc]
disable = []
EOF

  run env -i \
    HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_DATA_HOME="$home/.local/share" \
    XDG_STATE_HOME="$home/.local/state" \
    ANTIDOTE_HOME="$root" \
    ANTIDOTE_TEST_GIT_ROOT="$root" \
    ANTIDOTE_TEST_LOG="$log" \
    GIT_CONFIG_NOSYSTEM="$GIT_CONFIG_NOSYSTEM" \
    GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
    GIT_OPTIONAL_LOCKS="$GIT_OPTIONAL_LOCKS" \
    GIT_GUARD_LOG="$BATS_TEST_TMPDIR/topgrade-git.log" \
    NIX_PROFILES="" \
    PATH="$LOADER_FIXTURE_PATH" \
    SHELL="$ZSH_BIN" \
    TERM="dumb" \
    TMPDIR="$BATS_TEST_TMPDIR" \
    "$TOPGRADE_BIN" --dry-run --only shell --config "$config"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -Fc 'antidote update; exit $?' || true)" -eq 1 ]
  assert_no_network_git "$BATS_TEST_TMPDIR/topgrade-git.log"
}
