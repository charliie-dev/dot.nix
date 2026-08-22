{ config, lib, ... }:
{
  # binary 自我管理(package = null)後,上游 module 的 onChange 退化成裸呼叫
  # `herdr`,但 activation script 的 PATH 沒有 ~/.local/bin,switch 後的
  # auto reload 因此靜默失效。改回絕對路徑。
  xdg.configFile."herdr/config.toml".onChange = lib.mkForce ''
    ${config.home.homeDirectory}/.local/bin/herdr server reload-config || true
  '';
}
