{ pkgs, ... }:
let
  # activation script 的 PATH 沒有 pkill,要用絕對路徑
  pkill = if pkgs.stdenv.hostPlatform.isDarwin then "/usr/bin/pkill" else "${pkgs.procps}/bin/pkill";
in
{
  xdg.configFile."ghostty" = {
    recursive = true;
    source = ./ghostty;
    # Ghostty 1.2+ 收到 SIGUSR2 會 reload config,switch 後自動觸發
    onChange = "${pkill} -USR2 -x ghostty || true";
  };
}
