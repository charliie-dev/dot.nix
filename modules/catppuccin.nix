{
  catppuccin = {
    enable = true;
    # Pull whiskers-built ports (e.g. starship) from the official binary
    # cache instead of compiling whiskers locally. Injects the substituter +
    # key into nix.settings (merges with modules/nix-config.nix).
    cache.enable = true;
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
    television = {
      enable = true;
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
    # NOTE: no zsh-syntax-highlighting port — the active highlighter is
    # fast-syntax-highlighting (loaded via antidote), which ignores
    # ZSH_HIGHLIGHT_STYLES. Its Mocha theme lives in
    # conf.d/zsh/fast-syntax-highlighting.zsh instead.
  };
}
