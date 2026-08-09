{ lib, ... }:
let
  # Catppuccin Mocha for fast-syntax-highlighting. Home Manager's
  # fastSyntaxHighlighting.settings writes FAST_HIGHLIGHT, not this style map,
  # so generate the native associative-array assignments ourselves.
  styles = {
    command = "fg=#a6e3a1";
    builtin = "fg=#a6e3a1";
    function = "fg=#a6e3a1";
    alias = "fg=#a6e3a1";
    suffix-alias = "fg=#a6e3a1";
    global-alias = "fg=#a6e3a1";
    reserved-word = "fg=#a6e3a1";
    hashed-command = "fg=#a6e3a1";
    subcommand = "fg=#a6e3a1";
    precommand = "fg=#a6e3a1,italic";
    single-hyphen-option = "fg=#fab387";
    double-hyphen-option = "fg=#fab387";
    single-quoted-argument = "fg=#f9e2af";
    double-quoted-argument = "fg=#f9e2af";
    here-string-text = "fg=#f9e2af";
    back-quoted-argument = "fg=#cba6f7";
    here-string-var = "fg=#cba6f7";
    history-expansion = "fg=#cba6f7";
    globbing-ext = "fg=#cba6f7";
    path = "fg=#cdd6f4,underline";
    path-to-dir = "fg=#cdd6f4,underline";
    path_pathseparator = "fg=#f38ba8,underline";
    commandseparator = "fg=#f38ba8";
    back-dollar-quoted-argument = "fg=#f38ba8";
    unknown-token = "fg=#eba0ac";
    bracket-level-1 = "fg=#89b4fa,bold";
    bracket-level-2 = "fg=#cba6f7,bold";
    bracket-level-3 = "fg=#94e2d5,bold";
    paired-bracket = "bg=#585b70";
    comment = "fg=#585b70";
    default = "fg=#cdd6f4";
    globbing = "fg=#cdd6f4";
    redirection = "fg=#cdd6f4";
    assign = "fg=#cdd6f4";
    variable = "fg=#cdd6f4";
    mathvar = "fg=#cdd6f4";
    mathnum = "fg=#fab387";
  };
  assignments = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value: "FAST_HIGHLIGHT_STYLES[${name}]=${lib.escapeShellArg value}"
    ) styles
  );
in
{
  # F-Sy-H is deferred, and its defaults only fill unset styles. Define the
  # theme immediately before Antidote is sourced at order 550.
  initContent = lib.mkOrder 545 ''
    typeset -gA FAST_HIGHLIGHT_STYLES
    ${assignments}
  '';
}
