_:
let
  # activation script 的 PATH 沒有 rex;macOS 版 CLI 在 Rex Server.app 裡,其他平台不存在就跳過
  rex = "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
  # Rex.app 起的 server 聽這個 socket;沒有 REX_SERVER 時(例如 ssh 進來 switch)CLI 預設找
  # $TMPDIR/rex/server.sock,reload 會打不到 app 的 server,設定就停在舊版本。
  socket = "$HOME/Library/Application Support/rex/server.sock";
  socketUrl = "unix://$HOME/Library/Application%20Support/rex/server.sock";
in
{
  xdg.configFile."rex" = {
    recursive = true;
    source = ./rex;
    # Rex 不監看設定檔,switch 後主動 reload;--autostart=false 避免把沒在跑的 server 拉起來
    onChange = ''
      if [ -x "${rex}" ] && [ -S "${socket}" ]; then
        REX_SERVER="${socketUrl}" "${rex}" config reload --autostart=false || true
      fi
    '';
  };
}
