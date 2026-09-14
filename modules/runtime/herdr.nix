{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Local manifests replace all upstream rules; keep the Claude 2026.09.11.1 baseline.
  xdg.configFile."herdr/agent-detection/claude.toml" = {
    text = ''
      id = "claude"
      version = "2026.09.14.1"
      min_engine_version = 2
      updated_at = "2026-09-14T00:00:00Z"
      aliases = ["claude-code"]

      [[rules]]
      id = "osc_title_working"
      state = "working"
      priority = 1100
      region = "osc_title"
      visible_working = true
      # Braille covers <= 2.1.227; half-circles are the 2.1.228 busy spinner.
      regex = ['^[\x{2800}-\x{28FF}\x{25D0}-\x{25D3}] ']

      [[rules]]
      id = "live_turn_working"
      state = "working"
      priority = 970
      region = "bottom_non_empty_lines(12)"
      visible_working = true
      any = [
        { line_regex = ['^\s*[⏸⏵].*esc to interrupt(?:\s|·|$)'] },
        { line_regex = ['^\s*[\x{002A}\x{00B7}\x{2722}\x{2733}\x{2736}\x{273B}\x{273D}]\s+\S.*…(?:\s+\(\d+[smh](?:\s|·)|\s*$)'] },
      ]

      [[rules]]
      id = "background_agents_working"
      state = "working"
      priority = 965
      region = "last_non_empty_above_prompt_box"
      visible_working = true
      line_regex = ['^\s*[\x{002A}\x{00B7}\x{2722}\x{2736}\x{273B}\x{273D}]\s+Waiting for [1-9]\d* background agents? to finish\s*$']

      [[rules]]
      id = "background_mcp_task_working"
      state = "working"
      priority = 965
      region = "bottom_non_empty_lines(12)"
      visible_working = true
      # Claude renders activity summaries at column zero; wrapped continuations are indented.
      regex = ['(?m)^[\x{002A}\x{00B7}\x{2722}\x{2736}\x{273B}\x{273D}][ \t]+\S[^\n]*?(?:\n[ \t]+[^\n]*?){0,3}·(?:[ \t]+|\n[ \t]*)[1-9]\d*(?:[ \t]+|\n[ \t]*)MCP(?:[ \t]+|\n[ \t]*)tasks?(?:[ \t]+|\n[ \t]*)still(?:[ \t]+|\n[ \t]*)running[ \t]*$']
      not = [
        { contains = ["do you want to proceed?"] },
        { contains = ["esc to cancel"] },
        { contains = ["waiting for permission"] },
        { contains = ["do you want to allow this connection?"] },
        { contains = ["tab to amend"] },
        { contains = ["ctrl+e to explain"] },
      ]

      [[rules]]
      id = "background_shells_working"
      state = "working"
      priority = 960
      region = "whole_recent"
      visible_working = true
      # A live footer can wrap, but cannot have another prompt border below it.
      regex = ['(?m)^\s*(?:[⏵⏸][^─]*·\s*)?[1-9][0-9]*\s+shells?(?:\s+·[^─]*)?\s*\z']
      # Match control rows, not quoted phrases; allow one divider before the footer.
      not = [
        { regex = ['(?im)^[ \t]*(?:(?:do you want to|would you like to|select model)[^\n]*|(?:esc to cancel|waiting for permission|tab to amend|ctrl\+e to explain|review your answers|skip interview and plan immediately)(?:[ \t]+·[^\n]*)?)[ \t]*\n[^─]*(?:─+[^\n]*\n[^─]*)?\z'] },
      ]

      [[rules]]
      id = "btw_overlay_working"
      state = "working"
      priority = 975
      region = "bottom_non_empty_lines(5)"
      visible_working = true
      line_regex = [
        '^\s*/btw(?:\s|$)',
        '(?i)esc to close\s*$',
      ]

      [[rules]]
      id = "transcript_viewer"
      state = "unknown"
      priority = 1000
      region = "bottom_non_empty_lines(3)"
      skip_state_update = true
      contains = ["showing detailed transcript"]
      any = [
        { contains = ["ctrl+o", "to toggle"] },
        { contains = ["ctrl+e", "show all"] },
        { contains = ["ctrl+e", "collapse"] },
        { contains = ["↑↓ scroll"] },
        { contains = ["? for shortcuts"] },
      ]

      [[rules]]
      id = "live_blocked_form"
      state = "blocked"
      priority = 980
      region = "after_last_horizontal_rule"
      visible_blocker = true
      contains = ["esc to cancel"]
      any = [
        { contains = ["enter to confirm"] },
        { contains = ["enter to select"], any = [
          { contains = ["tab/arrow keys to navigate"] },
          { contains = ["arrow keys to navigate"] },
          { contains = ["arrows to navigate"] },
          { contains = ["↑/↓ to navigate"] },
          { contains = ["↑↓ to navigate"] },
        ] },
      ]

      [[rules]]
      id = "dynamic_workflow_prompt"
      state = "blocked"
      priority = 980
      region = "whole_recent"
      visible_blocker = true
      contains = ["run a dynamic workflow?", "esc to cancel"]

      [[rules]]
      id = "mcp_elicitation_prompt"
      state = "blocked"
      priority = 980
      region = "whole_recent"
      visible_blocker = true
      contains = ["esc to cancel"]
      line_regex = ['(?i)^\s*MCP server ["\x{201C}].+["\x{201D}] requests your input\s*$']
      all = [
        { any = [
          { line_regex = ['^\s*\x{276F}?\s*Accept\b'] },
          { line_regex = ['^\s*\x{276F}?\s*Decline\b'] },
        ] },
      ]

      [[rules]]
      id = "live_prompt_box"
      state = "idle"
      priority = 950
      region = "prompt_box_body"
      visible_idle = true
      line_regex = ['^\s*❯']
      not = [
        { contains = ["enter to select"] },
        { contains = ["esc to cancel"] },
        { contains = ["tab/arrow keys"] },
        { contains = ["arrow keys to navigate"] },
        { contains = ["↑/↓ to navigate"] },
      ]

      [[rules]]
      id = "model_picker_menu"
      state = "unknown"
      priority = 900
      region = "whole_recent"
      skip_state_update = true
      contains = ["select model", "enter to set as default", "esc to cancel"]
      not = [
        { contains = ["do you want to proceed?"] },
        { contains = ["enter to select"] },
      ]

      [[rules]]
      id = "bash_permission_prompt"
      state = "blocked"
      priority = 850
      region = "whole_recent"
      visible_blocker = true
      contains = ["do you want to proceed?"]
      any = [
        { contains = ["bash command"] },
        { contains = ["bash("] },
        { contains = ["contains expansion"] },
        { contains = ["tab to amend"] },
        { contains = ["ctrl+e to explain"] },
      ]
      # The selected option carries a ❯ prefix in both numbered and unnumbered menus.
      all = [
        { any = [
          { line_regex = ['(?i)^\s*❯?\s*yes\b'] },
          { line_regex = ['(?i)^\s*❯?\s*1\.\s*yes\b'] },
          { line_regex = ['(?i)^\s*❯?\s*2\.\s*yes\b'] },
          { line_regex = ['(?i)^\s*❯?\s*2\.\s*no\b'] },
          { line_regex = ['(?i)^\s*❯?\s*3\.\s*no\b'] },
        ] },
      ]

      [[rules]]
      id = "generic_permission_prompt"
      state = "blocked"
      priority = 840
      region = "after_last_horizontal_rule"
      visible_blocker = true
      contains = ["do you want to proceed?", "esc to cancel"]
      all = [
        { any = [
          { line_regex = ['(?i)^\s*❯?\s*1\.\s*yes\b'] },
          { line_regex = ['(?i)^\s*2\.\s*yes\b'] },
          { line_regex = ['(?i)^\s*2\.\s*no\b'] },
          { line_regex = ['(?i)^\s*3\.\s*no\b'] },
        ] },
      ]

      [[rules]]
      id = "legacy_no_prompt_blocker"
      state = "blocked"
      priority = 300
      region = "whole_recent"
      any = [
        { contains = ["do you want to"], any = [{ contains = ["yes"] }, { contains = ["❯"] }] },
        { contains = ["would you like to"], any = [{ contains = ["yes"] }, { contains = ["❯"] }] },
        { contains = ["waiting for permission"] },
        { contains = ["do you want to allow this connection?"] },
        { contains = ["tab to amend"] },
        { contains = ["ctrl+e to explain"] },
        { contains = ["do you want to proceed?", "esc to cancel"] },
        { contains = ["review your answers"] },
        { contains = ["skip interview and plan immediately"] },
      ]
      not = [
        { regex = ['(?m)^\s*❯\s*$'] },
      ]

      [[rules]]
      id = "osc_title_idle"
      state = "idle"
      priority = 250
      region = "osc_title"
      visible_idle = true
      regex = ['^\x{2733} ']

      [[rules]]
      id = "osc_progress_idle"
      state = "idle"
      priority = 250
      region = "osc_progress"
      regex = ['^4;0']
    '';
    onChange = ''
      ${config.home.homeDirectory}/.local/bin/herdr server reload-agent-manifests || true
    '';
  };

  # Grok detection overrides cover plan approval, background work, and
  # the active foreground footer in Grok 1.0.30.
  xdg.configFile."herdr/agent-detection/grok.toml" = {
    text = ''
      id = "grok"
      version = "2026.09.13.1"
      min_engine_version = 3
      updated_at = "2026-09-13T00:00:00Z"
      aliases = ["grok-build"]

      [[rules]]
      id = "osc_title_blocked"
      state = "blocked"
      priority = 1300
      region = "osc_title"
      visible_blocker = true
      contains = ["Action Required"]

      [[rules]]
      id = "plan_approval_blocked"
      state = "blocked"
      priority = 1210
      region = "bottom_non_empty_lines(2)"
      visible_blocker = true
      any = [
        { contains = ["a:approve", "q:quit plan"] },
        { line_regex = ['^\s*╰─.*· plan approval\b.*─╯\s*$'] },
      ]

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
      id = "foreground_hints_working"
      state = "working"
      priority = 1165
      region = "bottom_non_empty_lines(2)"
      visible_working = true
      contains = ["ctrl+.:shortcuts"]
      line_regex = ['^\s*(?:Shift\+Tab:mode\s+│\s+)?Ctrl\+b:send to bg(?:\s+│\s*(?:Ctrl\+\.:shortcuts)?)?\s*$']

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
