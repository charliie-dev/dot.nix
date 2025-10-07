{ pkgs, ... }:
{
  tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    secureSocket = true;
    terminal = "tmux-256-color";
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.tmux-fzf # prefix + F
      {
        # automatically saves sessions for you every 15 minutes
        # `prefix+Ctrl+s` to save, `prefix+Ctrl+r` to restore
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-save-interval '15'
               set -g @continuum-restore 'off'
        '';
      }
      {
        plugin = tmuxPlugins.prefix-highlight;
        extraConfig = ''
          set -g @prefix_highlight_prefix_prompt 'Wait'
          set -g @prefix_highlight_copy_prompt 'Copy'
          set -g @prefix_highlight_sync_prompt 'Sync'
        '';
      }
      {
        # persist tmux sessions after computer restart
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect"
        '';
      }
      {
        # add zoxide and fzf support for tmux session
        # `prefix + T` to open session wizard
        plugin = tmuxPlugins.session-wizard;
        extraConfig = ''
          set -g @session-wizard 'T'
        '';
      }
      {
        plugin = tmuxPlugins.yank;
        extraConfig = ''
          set -g @yank_selection 'chipboard'
          set -g @yank_selection_mouse 'clipboard'
          set -g @custom_copy_command 'yank > #{pane_tty}'
        '';
      }
    ];
    extraConfig = ''
      ${builtins.readFile ../../conf.d/tmux/tmux.conf}
    '';
  };
}
