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
      "zsh-users/zsh-autosuggestions kind:defer"
      "zdharma-continuum/fast-syntax-highlighting kind:defer"
      "zsh-users/zsh-history-substring-search kind:defer"
      "MichaelAquilina/zsh-you-should-use kind:defer"
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
      "mattmc3/zephyr path:plugins/homebrew"
      "mattmc3/zephyr path:plugins/macos"
    ];
  };
}
