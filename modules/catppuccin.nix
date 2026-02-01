{
  catppuccin = {
    # accent = "green";
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
