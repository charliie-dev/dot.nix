# Command-line syntax highlighter for Zsh; replaces fast-syntax-highlighting.
# Imported as a full module by apps/default.nix because it configures
# home.packages and xdg.configFile, not just a programs.* attribute.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Active theme. Either a built-in name (`zsh-patina list-themes` prints them
  # all: patina, catppuccin-mocha, nord, tokyonight, ...) or "custom" to use
  # `palette` below.
  activeTheme = "custom";

  # zsh-patina's built-in catppuccin-mocha theme, transcribed. It has no
  # "inherit a built-in theme" mechanism, so a custom theme is always a
  # complete file and the base has to be spelled out for `overrides` to sit on
  # top of. These hex codes are Mocha-specific and do not follow
  # catppuccin.flavor. Scope names follow the Sublime Text convention and the
  # most specific match wins; `zsh-patina list-scopes` prints every scope the
  # highlighter can emit.
  mocha = {
    source = "#cdd6f4";
    comment = "#9399b2";
    string = "#a6e3a1";
    keyword = "#cba6f7";
    "keyword.operator" = "#94e2d5";
    "keyword.operator.regexp" = "#f5c2e7";
    constant = "#fab387";
    "constant.character" = "#f5c2e7";
    storage = "#f9e2af";
    "storage.modifier" = "#cba6f7";
    support = "#89b4fa";
    "variable.function" = "#89b4fa";
    "variable.other" = "#f38ba8";
    "variable.parameter" = "#eba0ac";
    "variable.language.tilde" = "#f38ba8";
    "entity.name.function" = "#89b4fa";
    "punctuation.definition.variable" = "#f38ba8";
    "punctuation.section" = "#9399b2";
    "punctuation.terminator" = "#9399b2";
    "meta.group.expansion.history" = "#f38ba8";
    "dynamic.callable" = "#89b4fa";
    "dynamic.callable.missing" = "#f38ba8";
    "dynamic.path".underline = true;
    "meta.group.expansion.command.parens".foreground = "#cdd6f4";
  };

  # Deviations from upstream Mocha. `entity.name.function` is the name in a
  # `foo() { ... }` definition rather than an invocation; it moves with the
  # commands so definitions and calls do not end up different colors.
  overrides = {
    # commands
    "variable.function" = "#a6e3a1";
    "dynamic.callable" = "#a6e3a1";
    "entity.name.function" = "#a6e3a1";

    # options
    "variable.parameter" = "#fab387";

    # quoted strings
    string = "#89b4fa";

    # command not found
    "dynamic.callable.missing" = "#eba0ac";
  };

  palette = mocha // overrides;

  useCustom = activeTheme == "custom";
  themeFile = "${config.xdg.configHome}/zsh-patina/theme.toml";
  toToml = (pkgs.formats.toml { }).generate;
in
{
  # Also puts the CLI on PATH for `zsh-patina restart|status|check` and ships
  # its completion under share/zsh/site-functions, which Home Manager adds to
  # fpath from the profile directory.
  home.packages = [ pkgs.zsh-patina ];

  # The daemon caches the theme on start, so config changes are invisible until
  # it is restarted. `restart` recreates the socket in place; `stop` would leave
  # already-open shells unhighlighted until they are restarted themselves.
  home.activation.zshPatinaRestart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe pkgs.zsh-patina} restart > /dev/null || true
  '';

  xdg.configFile = {
    "zsh-patina/config.toml".source = toToml "zsh-patina-config.toml" {
      highlighting.theme = if useCustom then "file:${themeFile}" else activeTheme;
    };
  }
  // lib.optionalAttrs useCustom {
    "zsh-patina/theme.toml".source = toToml "zsh-patina-theme.toml" palette;
  };

  # `activate` emits code tied to the running daemon and must not be cached,
  # so this bypasses smartcache. Upstream wants the call last in .zshrc, hence
  # the order past keybindings at 1300. Antidote's deferred plugins still run
  # after this, which is the order zsh-autosuggestions expects.
  programs.zsh.initContent = lib.mkOrder 1400 ''
    eval "$(${lib.getExe pkgs.zsh-patina} activate)"
  '';
}
