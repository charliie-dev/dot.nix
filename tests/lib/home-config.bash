# 測試共用 helper:從 hostname 推導要 build 的 homeConfigurations 名稱,
# 讓同一份測試在每台機器上都能跑,不必寫死某一台的 host。
#
# hosts.nix 的 key 是 "<user>@<short hostname>"(macOS 另有 .local 變體,
# 那是給 home-manager switch 用的,測試一律用 short name)。
# 要測別台的設定就覆寫 HM_CONFIG,例如 HM_CONFIG=charles@pluto bats tests/...

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

home_config_name() {
  echo "${HM_CONFIG:-$(id -un)@$(hostname -s)}"
}

# 這台機器的 homeConfiguration 存在才有意義跑後續斷言;不存在時直接 skip,
# 而不是讓 nix 丟一個看不懂的 attribute missing。
require_home_config() {
  local name
  name="$(home_config_name)"
  nix eval --impure --expr \
    "builtins.hasAttr \"$name\" (builtins.getFlake \"git+file://$REPO\").homeConfigurations" \
    2>/dev/null | grep -q true || skip "no homeConfiguration named $name in hosts.nix"
}

build_home_package() {
  local name="$1"
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; ps = f.homeConfigurations.\"$(home_config_name)\".config.home.packages; in builtins.head (builtins.filter (p: (p.name or \"\") == \"$name\") ps)"
}
