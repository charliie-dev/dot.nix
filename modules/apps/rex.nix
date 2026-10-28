_:
let
  # activation script 的 PATH 沒有 rex;macOS 版 CLI 在 Rex Server.app 裡,其他平台不存在就跳過
  rex = "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
in
{
  xdg.configFile."rex" = {
    recursive = true;
    source = ./rex;
    # Rex 不監看設定檔,switch 後主動 reload;--autostart=false 避免把沒在跑的 server 拉起來
    onChange = ''
      if [ -x "${rex}" ]; then "${rex}" config reload --autostart=false || true; fi
    '';
  };
}
