# brew-env — 登入時把 code-agent 的 *_HOME 與 grok 隱私釘子設為 launchd
# 全域環境變數(gui domain),讓「非經 shell 啟動」的程式也解析到 XDG 路徑:
#   - GUI app:ChatGPT.app 內建的 codex(讀 CODEX_HOME)、Aside.app 的 daemon(讀 ASIDE_HOME)
#   - Dock/Finder/launchd 啟動的任何 brew cask / CLI
# shell 啟動的 CLI 已由 zsh.nix envExtra(.zshenv)覆蓋;此 agent 補上 GUI 那一段。
#
# 注意:launchctl setenv 只對「之後啟動」的程式生效 → 已開著的 app 需重啟才吃到。
# 用 nix 插值展開絕對路徑,因為 launchd 環境沒有 $XDG_* 變數。
# 未來其他 brew 工具要走 XDG 也往這裡加 setenv 即可。
{ config, pkgs, ... }:
{
  brew-env = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          /bin/launchctl setenv CLAUDE_CONFIG_DIR "${config.xdg.configHome}/claude"
          /bin/launchctl setenv CODEX_HOME "${config.xdg.configHome}/codex"
          /bin/launchctl setenv COPILOT_HOME "${config.xdg.configHome}/copilot"
          /bin/launchctl setenv GROK_HOME "${config.xdg.configHome}/grok"
          /bin/launchctl setenv MCP_REMOTE_CONFIG_DIR "${config.xdg.dataHome}/mcp-auth"
          /bin/launchctl setenv ASIDE_HOME "${config.xdg.dataHome}/aside"
          /bin/launchctl setenv GROK_TELEMETRY_ENABLED 0
          /bin/launchctl setenv GROK_FEEDBACK_ENABLED 0
          /bin/launchctl setenv GROK_TELEMETRY_TRACE_UPLOAD 0
          /bin/launchctl setenv GROK_DISABLE_AUTOUPDATER 1
        ''
      ];
      RunAtLoad = true;
    };
  };
}
