#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  require_home_config
}

@test "tombi uses the GitHub backend for Linux musl releases" {
  run nix eval --json --impure --expr "
    let
      flake = builtins.getFlake \"path:$REPO\";
      mise = flake.homeConfigurations.\"$(home_config_name)\".config.programs.mise.globalConfig;
    in
    {
      libc = mise.settings.libc;
      tombi = mise.tools.\"github:tombi-toml/tombi\" or null;
      hasRegistryAlias = builtins.hasAttr \"tombi\" mise.tools;
    }
  "
  [ "$status" -eq 0 ]

  result="$output"
  run jq -e '
    .libc == "gnu" and
    .tombi == {"exe": "tombi", "version": "latest"} and
    .hasRegistryAlias == false
  ' <<<"$result"
  [ "$status" -eq 0 ]
}
