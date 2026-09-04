{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Grok 1.x uses ◆ for its pinned background-work counter. Herdr 0.8.2's
  # bundled manifest only recognizes the older symbols, so keep the pane
  # working while background subagents or commands are still running.
  xdg.configFile."herdr/agent-detection/grok.toml" = {
    text = ''
      id = "grok"
      version = "2026.09.03.2"
      min_engine_version = 3
      updated_at = "2026-09-03T00:00:00Z"
      aliases = ["grok-build"]

      [[rules]]
      id = "osc_title_blocked"
      state = "blocked"
      priority = 1300
      region = "osc_title"
      visible_blocker = true
      contains = ["Action Required"]

      [[rules]]
      id = "option_dialog_blocked"
      state = "blocked"
      priority = 1200
      region = "whole_recent"
      visible_blocker = true
      line_regex = ['^\s*┃\s+[0-9a-z]+\s+\([●○]\)\s']

      [[rules]]
      id = "permission_hints_blocked"
      state = "blocked"
      priority = 1190
      region = "bottom_non_empty_lines(2)"
      visible_blocker = true
      contains = [":select", "ctrl+o:yolo", "ctrl+c:cancel"]

      [[rules]]
      id = "question_dialog_hints_blocked"
      state = "blocked"
      priority = 1185
      region = "bottom_non_empty_lines(2)"
      visible_blocker = true
      contains = ["tab:scrollback", "shift+x:dismiss"]

      [[rules]]
      id = "permission_scope_selector"
      state = "blocked"
      priority = 1180
      region = "whole_recent"
      visible_blocker = true
      contains = ["yes, proceed", "no, reject"]
      any = [
        { contains = ["use ← → to choose permission whitelist scope"] },
        { contains = ["←/→:scope"] },
      ]

      [[rules]]
      id = "background_work_status_working"
      state = "working"
      priority = 1175
      region = "bottom_non_empty_lines(6)"
      visible_working = true
      line_regex = ['^\s*[◎◉○]\s+.*\bstill running(?:\s+·\s+send a message to interrupt)?\s*$']

      [[rules]]
      id = "background_work_chip_working"
      state = "working"
      priority = 1170
      region = "top_non_empty_lines(1)"
      visible_working = true
      line_regex = ['◆\s+[1-9][0-9]*\s+│']

      [[rules]]
      id = "live_status_working"
      state = "working"
      priority = 1160
      region = "bottom_non_empty_lines(6)"
      visible_working = true
      line_regex = ['^\s*[⠋⠙⠹⠸⠼⠴⠦⠧]\s+.*\[stop\]\s*$']

      [[rules]]
      id = "osc_progress_working"
      state = "working"
      priority = 1150
      region = "osc_progress"
      visible_working = true
      regex = ['^4;1;-1$']

      [[rules]]
      id = "osc_title_idle"
      state = "idle"
      priority = 1100
      region = "osc_title"
      visible_idle = true
      regex = ['(?:^| - )grok$']
      not = [
        { regex = ['[\x{2800}-\x{28FF}]'] },
      ]

      [[rules]]
      id = "osc_title_working"
      state = "working"
      priority = 1000
      region = "osc_title"
      visible_working = true
      regex = ['\S']

      [[rules]]
      id = "osc_progress_idle"
      state = "idle"
      priority = 950
      region = "osc_progress"
      visible_idle = true
      regex = ['^4;0;0$']

      [[rules]]
      id = "spinner_status_working"
      state = "working"
      priority = 200
      region = "whole_recent"
      visible_working = true
      line_regex = ['^\s*[\x{2801}-\x{28FF}]\s.*\[stop\]\s*$']

      [[rules]]
      id = "esc_cancel_hints_working"
      state = "working"
      priority = 190
      region = "bottom_non_empty_lines(2)"
      visible_working = true
      contains = ["esc:cancel", "ctrl+.:shortcuts"]

      [[rules]]
      id = "waiting_tool_working"
      state = "working"
      priority = 120
      region = "whole_recent"
      visible_working = true
      any = [
        { all = [{ contains = ["ctrl+c:cancel", "ctrl+enter:interject"] }, { contains = ["waiting"] }] },
        { line_regex = ['^\s*[\x{2801}-\x{28FF}]\s+(Run|Read|Search|List)\b'] },
      ]

      [[rules]]
      id = "prompt_hints_idle"
      state = "idle"
      priority = 100
      region = "bottom_non_empty_lines(2)"
      visible_idle = true
      contains = ["ctrl+.:shortcuts"]
      not = [
        { contains = ["esc:cancel"] },
        { contains = ["ctrl+c:cancel"] },
      ]
    '';
    onChange = ''
      ${config.home.homeDirectory}/.local/bin/herdr server reload-agent-manifests || true
    '';
  };

  # Bootstrap 後的官方 binary 位於 ~/.local/bin,但 activation script 的
  # PATH 沒有這個目錄。用絕對路徑維持 switch 後的 auto reload。
  xdg.configFile."herdr/config.toml".onChange = lib.mkForce ''
    ${config.home.homeDirectory}/.local/bin/herdr server reload-config || true
  '';

  # Existing native installs can shadow the profile stub. Refresh generated
  # assets during switch without bootstrapping a missing binary.
  home.activation.herdrNativeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN_CMD:-}" ] && [ -x "${config.home.homeDirectory}/.local/bin/herdr" ]; then
      HOME="${config.home.homeDirectory}" \
        XDG_DATA_HOME="${config.xdg.dataHome}" \
        XDG_STATE_HOME="${config.xdg.stateHome}" \
        ${lib.getExe pkgs.herdr} --version > /dev/null || true
    fi
  '';
}
