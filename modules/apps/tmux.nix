{ pkgs, ... }:
{
  tmux = {
    enable = true;
    clock24 = true;
    escapeTime = 1;
    focusEvents = true;
    historyLimit = 64096;
    mouse = true;
    prefix = "C-a";
    secureSocket = true;
    terminal = "tmux-256color";
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
          set -g @yank_selection 'clipboard'
          set -g @yank_selection_mouse 'clipboard'
          set -g @custom_copy_command 'yank > #{pane_tty}'
        '';
      }
    ];
    extraConfig = ''
      # Allow Vim to receive modifier keys: Shift, Control, Alt.
      setw -g xterm-keys on

      # Enable clipboard through OSC52.
      set -g set-clipboard on
      setw -g allow-passthrough on
      bind -T copy-mode-vi 'Y' send -X copy-pipe-and-cancel 'yank > #{pane_tty}'
      set -ga terminal-overrides ',xterm*:Ms=\E]52;c;%p2%s\007'

      # Support yazi image previews and preserve terminal metadata.
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM

      # Detect Vim panes for seamless navigation.
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"

      # True color, strikethrough, and undercurl support.
      set -as terminal-overrides ",*-256col*:RGB"
      set -as terminal-overrides ',xterm*:smxx=\E[9m'
      set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
      set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

      # Let the title bar follow the connected host.
      set -g set-titles on
      set -g set-titles-string "#T"

      bind R source-file ~/.config/tmux/tmux.conf \; display-message "  Config reloaded!"

      # Session and pane navigation.
      bind ^u swapp -U
      bind ^d swapp -D
      bind s choose-tree
      bind S choose-session
      bind C-w new-window -n "Workspace-session-picker" "ta ~/Workspace"
      bind C-j new-window -n "session-switcher" "tmux list-sessions | sed -E 's/:.*$//' | grep -v \"^$(tmux display-message -p '#S')\$\" | fzf --reverse | xargs tmux switch-client -t"
      bind C-t new-session -A -s todo "cd ~/Workspace/todo && nvim -O backlog.md doing.md done.md"
      bind -n M-i new-session -A -s nvim "cd ~/.config/nvim/ && nvim"

      # Popup tools.
      bind -r l display-popup -d '#{pane_current_path}' -w80% -h80% -E lf
      bind -r g display-popup -d '#{pane_current_path}' -w80% -h80% -E lazygit
      bind -r n display-popup -w80% -h60% -E "navi --fzf-overrides '--height 100%'"
      bind -r t display-popup -w80% -h60% -E ncht

      # Broadcast a command to every pane in the current window.
      bind Space command-prompt -p "Command:" \
        "run \"tmux list-panes -a -F '##{session_name}:##{window_index}.##{pane_index}' \
          | xargs -I PANE tmux send-keys -t PANE '%1' Enter\""

      # Copy mode.
      setw -g mode-keys vi
      bind -T copy-mode-vi 'v' send -X begin-selection
      bind -T copy-mode-vi 'y' send -X copy-selection
      bind -T copy-mode-vi '-' send -X jump-again
      bind -T copy-mode-vi '_' send -X jump-reverse
      bind -T copy-mode-vi '?' command-prompt -p 'search-backward:' -I '#{pane_search_string}' -i 'send-keys -X search-backward-incremental "%%%"'
      bind -T copy-mode-vi '/' command-prompt -p 'search-forward:' -I '#{pane_search_string}' -i 'send-keys -X search-forward-incremental "%%%"'

      # Seamless Neovim/tmux pane navigation.
      bind -n 'C-h' if-shell "$is_vim" 'send-keys C-h' { if -F '#{pane_at_left}' "" 'select-pane -L' }
      bind -n 'C-j' if-shell "$is_vim" 'send-keys C-j' { if -F '#{pane_at_bottom}' "" 'select-pane -D' }
      bind -n 'C-k' if-shell "$is_vim" 'send-keys C-k' { if -F '#{pane_at_top}' "" 'select-pane -U' }
      bind -n 'C-l' if-shell "$is_vim" 'send-keys C-l' { if -F '#{pane_at_right}' "" 'select-pane -R' }
      bind -T copy-mode-vi 'C-h' if -F '#{pane_at_left}' "" 'select-pane -L'
      bind -T copy-mode-vi 'C-j' if -F '#{pane_at_bottom}' "" 'select-pane -D'
      bind -T copy-mode-vi 'C-k' if -F '#{pane_at_top}' "" 'select-pane -U'
      bind -T copy-mode-vi 'C-l' if -F '#{pane_at_right}' "" 'select-pane -R'

      # Seamless Neovim/tmux pane resizing.
      bind -n 'M-h' if-shell "$is_vim" 'send-keys M-h' 'resize-pane -L 1'
      bind -n 'M-j' if-shell "$is_vim" 'send-keys M-j' 'resize-pane -D 1'
      bind -n 'M-k' if-shell "$is_vim" 'send-keys M-k' 'resize-pane -U 1'
      bind -n 'M-l' if-shell "$is_vim" 'send-keys M-l' 'resize-pane -R 1'
      bind -T copy-mode-vi M-h resize-pane -L 1
      bind -T copy-mode-vi M-j resize-pane -D 1
      bind -T copy-mode-vi M-k resize-pane -U 1
      bind -T copy-mode-vi M-l resize-pane -R 1
    '';
  };
}
