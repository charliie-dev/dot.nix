# Darwin brew-env — 登入時把 code-agent 的 *_HOME 與 grok 隱私釘子設為 launchd
# 全域環境變數(gui domain),讓「非經 shell 啟動」的程式也解析到 XDG 路徑:
#   - GUI app:ChatGPT.app 內建的 codex(讀 CODEX_HOME)、Aside.app 的 daemon(讀 ASIDE_HOME)
#   - Dock/Finder/launchd 啟動的任何 brew cask / CLI
# shell 啟動的 CLI 已由 home.sessionVariables 覆蓋;此 agent 補上 GUI 那一段。
#
# 注意:launchctl setenv 只對「之後啟動」的程式生效 → 已開著的 app 需重啟才吃到。
# 用 nix 插值展開絕對路徑,因為 launchd 環境沒有 $XDG_* 變數。
# 未來其他 brew 工具要走 XDG 也往這裡加 setenv 即可。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  env = config.home.sessionVariables;
  # A named script rather than an inline `/bin/sh -c` body, so the process keeps
  # the agent's name instead of turning back into "sh" after exec.
  setenv = pkgs.writeShellScript "brew-env" ''
    /bin/launchctl setenv CLAUDE_CONFIG_DIR "${env.CLAUDE_CONFIG_DIR}"
    /bin/launchctl setenv CODEX_HOME "${env.CODEX_HOME}"
    /bin/launchctl setenv COPILOT_HOME "${env.COPILOT_HOME}"
    /bin/launchctl setenv GROK_HOME "${env.GROK_HOME}"
    /bin/launchctl setenv MCP_REMOTE_CONFIG_DIR "${env.MCP_REMOTE_CONFIG_DIR}"
    /bin/launchctl setenv ASIDE_HOME "${env.ASIDE_HOME}"
    /bin/launchctl setenv GROK_TELEMETRY_ENABLED "${env.GROK_TELEMETRY_ENABLED}"
    /bin/launchctl setenv GROK_FEEDBACK_ENABLED "${env.GROK_FEEDBACK_ENABLED}"
    /bin/launchctl setenv GROK_TELEMETRY_TRACE_UPLOAD "${env.GROK_TELEMETRY_TRACE_UPLOAD}"
    /bin/launchctl setenv GROK_STORAGE_MODE "${env.GROK_STORAGE_MODE}"
    /bin/launchctl setenv GROK_DISABLE_AUTOUPDATER "${env.GROK_DISABLE_AUTOUPDATER}"
    /bin/launchctl setenv COPILOT_AUTO_UPDATE "${env.COPILOT_AUTO_UPDATE}"
    /bin/launchctl setenv CODEGRAPH_TELEMETRY "${env.CODEGRAPH_TELEMETRY}"
    /bin/launchctl setenv CODEGRAPH_NO_UPDATE_CHECK "${env.CODEGRAPH_NO_UPDATE_CHECK}"
  '';
in
lib.mkIf pkgs.stdenv.isDarwin {
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
