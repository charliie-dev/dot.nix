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

@test "Darwin Docker plugin links match mise backend install paths" {
  run nix eval --json --impure --expr "
    let f = builtins.getFlake \"path:$REPO\"; in
    f.homeConfigurations.\"$(home_config_name)\".pkgs.stdenv.hostPlatform.isDarwin
  "
  [ "$status" -eq 0 ]
  [ "$output" = true ] || skip "Docker plugin links are Darwin-only"

  home_dir=$(nix eval --raw --impure --expr "
    let f = builtins.getFlake \"path:$REPO\"; in
    f.homeConfigurations.\"$(home_config_name)\".config.home.homeDirectory
  ")
  compose_source=$(nix build --no-link --print-out-paths --impure --expr "
    let f = builtins.getFlake \"path:$REPO\"; in
    f.homeConfigurations.\"$(home_config_name)\".config.xdg.configFile.\"docker/cli-plugins/docker-compose\".source
  ")
  buildx_source=$(nix build --no-link --print-out-paths --impure --expr "
    let f = builtins.getFlake \"path:$REPO\"; in
    f.homeConfigurations.\"$(home_config_name)\".config.xdg.configFile.\"docker/cli-plugins/docker-buildx\".source
  ")

  [ "$(readlink "$compose_source")" = "$home_dir/.local/share/mise/installs/github-docker-compose/latest/docker-compose" ]
  [ "$(readlink "$buildx_source")" = "$home_dir/.local/share/mise/installs/aqua-docker-buildx/latest/docker-cli-plugin-docker-buildx" ]
}
