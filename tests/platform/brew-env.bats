#!/usr/bin/env bats

load "../lib/home-config"

MODULE="$REPO/modules/platform/services/brew-env.nix"

setup() {
  # 這個 agent 是 lib.mkIf pkgs.stdenv.isDarwin,在 Linux 上根本不存在。
  [ "$(uname -s)" = Darwin ] || skip "brew-env is darwin-only"
  require_home_config
}

build_agent_script() {
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; in builtins.head f.homeConfigurations.\"$(home_config_name)\".config.launchd.agents.brew-env.config.ProgramArguments"
}

@test "gui doppler config dir is isolated from the one holding the login token" {
  grep -Fq 'dopplerGuiConfigDir = "${config.xdg.cacheHome}/doppler-gui"' "$MODULE"
  grep -Fq 'setenv DOPPLER_CONFIG_DIR "$dopplerGui"' "$MODULE"
  ! grep -Fq 'setenv DOPPLER_CONFIG_DIR "${env.DOPPLER_CONFIG_DIR}"' "$MODULE"
}

@test "gui doppler config dir is validated and reset before it is published" {
  # mkdir -p 對已存在的路徑不驗型別也不改 mode,所以佔位要先移掉、內容要先清,
  # 而且只有驗過的目錄才可以 setenv。少任何一條就等於替攻擊者的目錄蓋章。
  grep -Fq '[ -L "$dopplerGui" ]' "$MODULE"
  grep -Fq '/bin/rm -f "$dopplerGui"' "$MODULE"
  grep -Fq '/bin/chmod 700 "$dopplerGui"' "$MODULE"
  grep -Fq '/bin/rm -f "$dopplerGui/.doppler.yaml"' "$MODULE"
  grep -Fq '[ -d "$dopplerGui" ] && [ ! -L "$dopplerGui" ] && [ -O "$dopplerGui" ]' "$MODULE"
}

@test "the built agent script publishes the isolated path and nothing else" {
  script="$(build_agent_script)"
  grep -Fq "$HOME/.cache/doppler-gui" "$script"
  ! grep -Fq "$HOME/.config/doppler" "$script"
  # [ -O ] 是 bash 的 test 運算子;換成 dash 會靜默永不 setenv
  head -n1 "$script" | grep -q 'bash'
}
