#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  [ "$(uname -s)" = Darwin ] || skip "colima is darwin-only"
  require_home_config
}

teardown() {
  [ -z "${LIMACTL_PID:-}" ] || kill "$LIMACTL_PID" 2>/dev/null || true
}

agent_attr() {
  echo "(builtins.getFlake \"git+file://$REPO\").homeConfigurations.\"$(home_config_name)\".config.launchd.agents.colima-default.config"
}

# 只跑 pid 清理段落:把 exec 那行拿掉,避免真的啟動 colima。
cleanup_only() {
  script="$(nix build --no-link --print-out-paths --impure --expr "builtins.head $(agent_attr).ProgramArguments")"
  sed '/^exec /,$d' "$script" >"$BATS_TEST_TMPDIR/cleanup.sh"
}

@test "agent restarts after failed exits, throttled" {
  run nix eval --json --impure --expr "let c = $(agent_attr); in [ c.KeepAlive c.ThrottleInterval ]"
  [ "$status" -eq 0 ]
  [ "$output" = "[true,30]" ]
}

@test "stale pid files owned by non-limactl processes are removed" {
  cleanup_only
  dir="$BATS_TEST_TMPDIR/home/_lima/colima"
  mkdir -p "$dir"
  echo 1 >"$dir/vz.pid"      # launchd:PID 被重用
  echo 999999 >"$dir/ha.pid" # 不存在的 process
  COLIMA_HOME="$BATS_TEST_TMPDIR/home" bash "$BATS_TEST_TMPDIR/cleanup.sh"
  [ ! -e "$dir/vz.pid" ]
  [ ! -e "$dir/ha.pid" ]
}

@test "pid files owned by limactl are kept" {
  cleanup_only
  # 用名稱含 limactl 的 process 模擬 nixpkgs 的 .limactl-wrapped
  ln -s /bin/sleep "$BATS_TEST_TMPDIR/.limactl-wrapped"
  # 關掉 fd 3,否則背景 process 會讓 bats 等它結束;失敗時由 teardown 收掉
  "$BATS_TEST_TMPDIR/.limactl-wrapped" 30 3>&- &
  LIMACTL_PID=$!
  dir="$BATS_TEST_TMPDIR/lima/colima"
  mkdir -p "$dir"
  echo "$LIMACTL_PID" >"$dir/vz.pid"
  LIMA_HOME="$BATS_TEST_TMPDIR/lima" bash "$BATS_TEST_TMPDIR/cleanup.sh"
  [ -e "$dir/vz.pid" ]
}
