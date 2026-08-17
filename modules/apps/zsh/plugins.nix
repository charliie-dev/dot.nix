{ pkgs, ... }:

{
  antidote = {
    enable = true;
    useFriendlyNames = true;
    plugins = [
      # zsh-smartcache must be available before integrations.nix runs.
      "QuarticCat/zsh-smartcache"
      # Deferred plugins run FIFO after .zshrc has completed.
      "Aloxaf/fzf-tab kind:defer"
      # Syntax highlighting is zsh-patina (modules/apps/patina.nix), which
      # loads at order 545 so it is in place before this plugin list.
      "zsh-users/zsh-autosuggestions kind:defer"
      "zsh-users/zsh-history-substring-search kind:defer"
      "MichaelAquilina/zsh-you-should-use kind:defer"
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      "mattmc3/zephyr path:plugins/homebrew"
      "mattmc3/zephyr path:plugins/macos"
    ];
  };
}
