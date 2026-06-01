{
  catppuccin = {
    enable = true;
    # accent = "green";
    # autoEnable preserves pre-migration behavior: only the ports
    # explicitly enabled below are themed (no global auto-enrollment).
    # enable is now a global toggle gating all ports.
    autoEnable = false;
    flavor = "mocha";
    bat = {
      enable = true;
    };
    btop = {
      enable = true;
    };
    delta = {
      enable = true;
    };
    gh-dash = {
      enable = true;
    };
    lazygit = {
      enable = true;
    };
    lsd = {
      enable = true;
    };
    starship = {
      enable = true;
      # flavor = "macchiato"; # or frappe, macchiato, mocha
    };
    tmux = {
      enable = true;
      # flavor = "macchiato";
      extraConfig = ''
        set -g @catppuccin_window_tabs_enabled on
        set -g @catppuccin_host "on"
      '';
    };
    vivid = {
      enable = false;
    };
    yazi = {
      enable = true;
    };
    zsh-syntax-highlighting = {
      enable = true;
      # flavor = "frappe";
    };
  };
}
