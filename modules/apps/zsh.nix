args@{ lib, ... }:

{
  zsh = lib.mkMerge [
    (import ./zsh/core.nix args)
    (import ./zsh/aliases.nix args)
    (import ./zsh/functions.nix args)
    (import ./zsh/completion.nix args)
    (import ./zsh/plugins.nix args)
    (import ./zsh/integrations.nix args)
    (import ./zsh/highlighting.nix args)
    (import ./zsh/keybindings.nix args)
    (import ./zsh/darwin.nix args)
    (import ./zsh/linux.nix args)
  ];
}
