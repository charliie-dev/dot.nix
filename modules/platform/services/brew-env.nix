# Darwin brew-env — 登入時把 code-agent 的 *_HOME 與 grok 隱私釘子設為 launchd
# 全域環境變數(gui domain),讓「非經 shell 啟動」的程式也解析到 XDG 路徑:
#   - GUI app:ChatGPT.app 內建的 codex(讀 CODEX_HOME)、Aside.app 的 daemon(讀 ASIDE_HOME)
#   - Dock/Finder/launchd 啟動的任何 brew cask / CLI
# shell 啟動的 CLI 已由 home.sessionVariables 覆蓋;此 agent 補上 GUI 那一段。
#
# 注意:launchctl setenv 只對「之後啟動」的程式生效 → 已開著的 app 需重啟才吃到。
# 用 nix 插值展開絕對路徑,因為 launchd 環境沒有 $XDG_* 變數。
# 未來其他 brew 工具要走 XDG 也往這裡加 setenv 即可。
#
# DOPPLER_CONFIG_DIR 是唯一的例外,不取 sessionVariables 的值。doppler 沒有
# GUI app,只有 CLI 與 TUI(doppler tui),兩者都從 shell 啟動、吃 shell 端的
# ~/.config/doppler,所以這裡設的值在日常操作中根本讀不到 —— 只有「GUI 啟動
# 且不經 shell 的東西直接呼叫 doppler」才會碰到,例如 Raycast/Alfred 的 script
# command。那種情況指向空目錄,行為與改動前(落回 ~/.doppler)等價,差別是不在
# 家目錄留 dotfile,而且不會把 shell 端目錄裡的 / scope login token 一起交出去。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  env = config.home.sessionVariables;
  # gui domain 專用的空 config 目錄,不是 shell 端的 ${env.DOPPLER_CONFIG_DIR}。
  dopplerGuiConfigDir = "${config.xdg.cacheHome}/doppler-gui";
  # A named script rather than an inline `/bin/sh -c` body, so the process keeps
  # the agent's name instead of turning back into "sh" after exec.
  setenv = pkgs.writeShellScript "brew-env" ''
    /bin/launchctl setenv CLAUDE_CONFIG_DIR "${env.CLAUDE_CONFIG_DIR}"
    /bin/launchctl setenv CODEX_HOME "${env.CODEX_HOME}"
    /bin/launchctl setenv COPILOT_HOME "${env.COPILOT_HOME}"
    /bin/launchctl setenv GROK_HOME "${env.GROK_HOME}"
    /bin/launchctl setenv MCP_REMOTE_CONFIG_DIR "${env.MCP_REMOTE_CONFIG_DIR}"
    /bin/launchctl setenv ASIDE_HOME "${env.ASIDE_HOME}"
    # brew 版 doppler CLI,作用面見檔案開頭的例外說明。不用 shell 端的值是因為
    # 那個目錄的 / scope 帶 login token,設進 gui domain 等於把整個專案的憑證
    # 發給每個 GUI 啟動的行程(還會進 crash report、subprocess env dump)。
    # mkdir -p 對已存在的路徑直接成功返回,不驗型別也不改 mode,連「指向
    # ~/.config/doppler 的 symlink」都照樣放行,那正好是這裡要避開的目錄。
    # 先移掉非目錄的佔位,確認是自己擁有的實體目錄才 setenv;驗不過就不設,
    # doppler 會落回 ~/.doppler,家目錄髒但不會交出憑證。
    dopplerGui=${lib.escapeShellArg dopplerGuiConfigDir}
    if [ -L "$dopplerGui" ] || { [ -e "$dopplerGui" ] && [ ! -d "$dopplerGui" ]; }; then
      /bin/rm -f "$dopplerGui"
    fi
    /bin/mkdir -p "$dopplerGui" && /bin/chmod 700 "$dopplerGui"
    # 型別與擁有者驗過了,內容沒有。目錄先前被放進一份 .doppler.yaml 的話,
    # mkdir -p 會直接放行、chmod 700 也不動內容,等於替它蓋章;之後任何讀到
    # 這個目錄的 doppler 都會採信裡面的 api-host 與 verify-tls,而那次呼叫的
    # argv 不受這個 repo 控制。對齊 doppler-run 的 reset_run_config_file()。
    /bin/rm -f "$dopplerGui/.doppler.yaml"
    if [ -d "$dopplerGui" ] && [ ! -L "$dopplerGui" ] && [ -O "$dopplerGui" ]; then
      /bin/launchctl setenv DOPPLER_CONFIG_DIR "$dopplerGui"
    fi
    /bin/launchctl setenv GROK_TELEMETRY_ENABLED "${env.GROK_TELEMETRY_ENABLED}"
    /bin/launchctl setenv GROK_FEEDBACK_ENABLED "${env.GROK_FEEDBACK_ENABLED}"
    /bin/launchctl setenv GROK_TELEMETRY_TRACE_UPLOAD "${env.GROK_TELEMETRY_TRACE_UPLOAD}"
    /bin/launchctl setenv GROK_TELEMETRY_MIXPANEL_ENABLED "${env.GROK_TELEMETRY_MIXPANEL_ENABLED}"
    /bin/launchctl setenv GROK_STORAGE_MODE "${env.GROK_STORAGE_MODE}"
    /bin/launchctl setenv GROK_DISABLE_AUTOUPDATER "${env.GROK_DISABLE_AUTOUPDATER}"
    /bin/launchctl setenv COPILOT_AUTO_UPDATE "${env.COPILOT_AUTO_UPDATE}"
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  launchd.agents.brew-env = {
    enable = true;
    # Show up as "brew-env" instead of "sh" in Login Items & Extensions. The agent
    # runs in the `gui` domain (HM default), which starts after GUI login, so the
    # Nix Store volume is already mounted and /bin/wait4path buys nothing.
    waitForNixStore = false;
    config = {
      ProgramArguments = [ "${setenv}" ];
      RunAtLoad = true;
    };
  };
}
