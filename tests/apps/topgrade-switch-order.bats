#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  require_home_config
  command -v topgrade >/dev/null || skip "topgrade is not installed"
}

build_topgrade_config() {
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.xdg.configFile.\"topgrade.toml\".source"
}

@test "topgrade runs built-in updates before one home-manager switch" {
  config_dir="$BATS_TEST_TMPDIR/topgrade"
  mkdir -p "$config_dir/topgrade.d"
  cp "$(build_topgrade_config)" "$config_dir/topgrade.toml"
  cp "$REPO/conf.d/topgrade/disable.toml" "$config_dir/topgrade.d/disable.toml"

  run env XDG_CONFIG_HOME="$config_dir" topgrade --dry-run
  [ "$status" -eq 0 ]

  config_errors=$(printf '%s\n' "$output" | grep -Eic 'unknown variant|configuration.*error|failed to (parse|deserialize)' || true)
  switch_count=$(printf '%s\n' "$output" | grep -Ec 'nh home switch|home-manager switch' || true)
  antidote_count=$(printf '%s\n' "$output" | grep -Fc 'antidote update; exit $?' || true)
  determinate_count=$(printf '%s\n' "$output" | grep -Fc 'determinate-nixd upgrade' || true)
  channel_count=$(printf '%s\n' "$output" | grep -Fc 'nix-channel --update' || true)
  profile_count=$(printf '%s\n' "$output" | grep -Fc 'nix-env --upgrade' || true)
  topgrade_self_update_count=$(printf '%s\n' "$output" | grep -Fc 'Would self-update' || true)
  mise_plugins_count=$(printf '%s\n' "$output" | grep -Fc 'mise plugins update' || true)
  mise_self_update_count=$(printf '%s\n' "$output" | grep -Fc 'mise self-update' || true)
  git_line=$(printf '%s\n' "$output" | grep -n 'Git repositories' | head -n 1 | cut -d: -f1)
  determinate_line=$(printf '%s\n' "$output" | grep -nF 'determinate-nixd upgrade' | head -n 1 | cut -d: -f1)
  home_manager_line=$(printf '%s\n' "$output" | grep -nE 'home-manager switch[[:space:]]*$' | head -n 1 | cut -d: -f1)

  [ "$config_errors" -eq 0 ]
  [ "$switch_count" -eq 1 ]
  [ "$antidote_count" -eq 1 ]
  [ "$determinate_count" -eq 1 ]
  [ "$channel_count" -eq 1 ]
  [ "$profile_count" -eq 1 ]
  [ "$topgrade_self_update_count" -eq 1 ]
  [ "$mise_plugins_count" -eq 1 ]
  [ "$mise_self_update_count" -eq 1 ]
  [ "$git_line" -lt "$determinate_line" ]
  [ "$determinate_line" -lt "$home_manager_line" ]
}
