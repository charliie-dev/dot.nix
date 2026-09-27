#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  bats_require_minimum_version 1.5.0
  require_home_config
}

@test "ruff cache and bash history use XDG paths without exporting HISTFILE globally" {
  run --separate-stderr nix eval --json --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; c = f.homeConfigurations.\"$(home_config_name)\".config; in {
      ruff = c.home.sessionVariables.RUFF_CACHE_DIR == c.xdg.cacheHome + \"/ruff\";
      bash = c.programs.bash.enable && c.programs.bash.historyFile == c.xdg.stateHome + \"/bash/history\";
      package = c.programs.bash.package == null;
      scoped = !(c.home.sessionVariables ? HISTFILE);
      zsh = c.programs.zsh.history.path == c.xdg.stateHome + \"/zsh/history\";
    }"
  [ "$status" -eq 0 ]
  run jq -e 'all(.[]; . == true)' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "configured bash startup builds with runtime mise completion" {
  run --separate-stderr nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".config.home.file.\".bashrc\".source"
  [ "$status" -eq 0 ]
  bashrc="$output"
  [ -f "$bashrc" ]
  grep -Fq 'activate bash' "$bashrc"
  grep -Fq 'bash-completion/completions/mise.bash' "$bashrc"
  run env -u BASH_ENV bash --noprofile --norc -n "$bashrc"
  [ "$status" -eq 0 ]
}

@test "bash creates and writes history in its XDG state directory" {
  test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$test_home"
  bashrc=$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; h = f.inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = f.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
      modules = [
        ({ config, ... }: {
          programs = import $REPO/modules/apps/bash.nix { inherit config; };
        })
        {
          home.username = \"xdg-test\";
          home.homeDirectory = \"$test_home\";
          home.stateVersion = \"26.05\";
          xdg.enable = true;
          programs.bash.enableCompletion = false;
        }
      ];
    }; in h.config.home.file.\".bashrc\".source")

  run env -i HOME="$test_home" PATH="$PATH" HISTFILE="$test_home/legacy-history" \
    bash --noprofile --rcfile "$bashrc" -ic 'history -s xdg_history_probe; history -w'
  [ "$status" -eq 0 ]
  [ -f "$test_home/.local/state/bash/history" ]
  [[ "$(<"$test_home/.local/state/bash/history")" == *xdg_history_probe* ]]
  [ ! -e "$test_home/.bash_history" ]
  [ ! -e "$test_home/legacy-history" ]
}

@test "ruff writes its cache to RUFF_CACHE_DIR" {
  command -v ruff >/dev/null || skip "ruff is not installed"
  test_home="$BATS_TEST_TMPDIR/home"
  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$test_home" "$project"
  printf 'value = 1\n' >"$project/example.py"

  run env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
    RUFF_CACHE_DIR="$test_home/.cache/ruff" ruff check "$project/example.py"
  [ "$status" -eq 0 ]
  [ -d "$test_home/.cache/ruff" ]
  [ ! -e "$project/.ruff_cache" ]
  [ ! -e "$test_home/.ruff_cache" ]
}
