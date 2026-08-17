#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  require_home_config
}

@test "runtime binary updaters are not Home Manager activation entries" {
  generation=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".activationPackage")

  run grep -E 'upgradeMise|upgradeTopgrade' "$generation/activate"
  [ "$status" -ne 0 ]
}

@test "mise stub preserves the packaged Zsh completion" {
  package=$(nix eval --raw --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.programs.mise.package.outPath")

  [ -e "$package/share/zsh/site-functions/_mise" ]
}
