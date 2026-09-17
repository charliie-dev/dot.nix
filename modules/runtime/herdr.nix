{
  config,
  lib,
  pkgs,
  ...
}:
let
  upstreamManifest =
    agent: sha256:
    builtins.readFile (
      builtins.fetchurl {
        url = "https://raw.githubusercontent.com/herdrdev/herdr/v0.9.1/src/detect/manifests/${agent}.toml";
        inherit sha256;
      }
    );
  # Local manifests replace upstream rules rather than merging with them.
  withLocalRules =
    base: rules:
    let
      metadata = builtins.fromTOML base;
    in
    builtins.replaceStrings
      [
        ''version = "${metadata.version}"''
        ''updated_at = "${metadata.updated_at}"''
      ]
      [
        ''version = "2026.09.17.1"''
        ''updated_at = "2026-09-17T00:00:00Z"''
      ]
      base
    + rules;
  claudeUpstream = upstreamManifest "claude" "sha256-A40Koj/uP5s5yzycoRfQ+VsLOlhzzw84KEzLrCeclmQ=";
  grokUpstream = upstreamManifest "grok" "sha256-YYr8PQnXhDQ/xsS87lgBkG3ywP1ipltEfPX0sb0hW7I=";
  # Grok 1.0.30 also uses a diamond for its background-task count.
  grokBase =
    builtins.replaceStrings
      [ ''line_regex = ['[⋅:⸬⁙.·]\s+[1-9][0-9]*\s+│']'' ]
      [ ''line_regex = ['[◆⋅:⸬⁙.·]\s+[1-9][0-9]*\s+│']'' ]
      grokUpstream;
in
{
  xdg.configFile."herdr/agent-detection/claude.toml" = {
    text = withLocalRules claudeUpstream ''

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
    '';
    onChange = ''
      ${config.home.homeDirectory}/.local/bin/herdr server reload-agent-manifests || true
    '';
  };

  xdg.configFile."herdr/agent-detection/grok.toml" = {
    text = withLocalRules grokBase ''

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
      id = "background_work_status_working"
      state = "working"
      priority = 1175
      region = "bottom_non_empty_lines(6)"
      visible_working = true
      line_regex = ['^\s*[◎◉○]\s+.*\bstill running(?:\s+·\s+send a message to interrupt)?\s*$']

      [[rules]]
      id = "background_dock_working"
      state = "working"
      priority = 1168
      region = "whole_recent"
      visible_working = true
      # Require a working row in the dock before the final Grok prompt box.
      regex = ['(?m)^[ \t]*▾[ \t]+(?:Tasks|Subagents|Watches|Watchers)[ \t]+[1-9][0-9]*[ \t]*\n(?:[^\n╭╰]*\n)*?[ \t]*[⋅:⸬⁙][ \t]+\S[^\n]*\n[^╭╰]*╭─+[^\n]*╮\n(?:[ \t]*│[^\n]*\n)+[ \t]*╰─+[^\n]*╯(?:\n[^╭╰]*)?\z']

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
