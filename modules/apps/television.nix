{
  television = {
    enable = true;
    # CTRL-T / CTRL-R belong to the fzf widgets (zsh/integrations.nix); run `tv` directly.
    enableZshIntegration = false;
    settings = {
      default_channel = "nix-search-tv";
      keybindings = {
        esc = "quit";
        ctrl-c = "quit";
        ctrl-n = "actions:nvim";
      };
      actions = {
        nvim = {
          description = "Pipe to nvim";
          command = "man '{0}' | nvim";
          mode = "fork";
        };
      };
    };
    # channels = { };
  };
}
