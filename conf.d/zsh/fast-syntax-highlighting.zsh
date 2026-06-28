# Catppuccin Mocha theme for fast-syntax-highlighting (F-Sy-H).
#
# F-Sy-H is loaded via antidote with `kind:defer`, so it sources *after* this
# file runs. Its defaults use `: ${FAST_HIGHLIGHT_STYLES[k]:=...}` (assign only
# if unset), so values pre-set here survive the plugin load — no defer-ordering
# hook needed. catppuccin/nix only ships a z-sy-h port (ZSH_HIGHLIGHT_STYLES,
# which F-Sy-H ignores), hence these manual hex codes, mirroring the official
# catppuccin-mocha z-sy-h palette. Keep in sync with modules/catppuccin.nix.
typeset -gA FAST_HIGHLIGHT_STYLES

# Commands & friends — Green
FAST_HIGHLIGHT_STYLES[command]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[builtin]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[function]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[alias]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[suffix-alias]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[global-alias]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[reserved-word]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[hashed-command]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[subcommand]='fg=#a6e3a1'
FAST_HIGHLIGHT_STYLES[precommand]='fg=#a6e3a1,italic'

# Options — Peach
FAST_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#fab387'
FAST_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#fab387'

# Quotes & strings — Yellow
FAST_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#f9e2af'
FAST_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#f9e2af'
FAST_HIGHLIGHT_STYLES[here-string-text]='fg=#f9e2af'

# Substitution / expansion — Mauve
FAST_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#cba6f7'
FAST_HIGHLIGHT_STYLES[here-string-var]='fg=#cba6f7'
FAST_HIGHLIGHT_STYLES[history-expansion]='fg=#cba6f7'
FAST_HIGHLIGHT_STYLES[globbing-ext]='fg=#cba6f7'

# Paths — Text + underline, separators in Red
FAST_HIGHLIGHT_STYLES[path]='fg=#cdd6f4,underline'
FAST_HIGHLIGHT_STYLES[path-to-dir]='fg=#cdd6f4,underline'
FAST_HIGHLIGHT_STYLES[path_pathseparator]='fg=#f38ba8,underline'

# Separators & errors — Red / Maroon
FAST_HIGHLIGHT_STYLES[commandseparator]='fg=#f38ba8'
FAST_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=#f38ba8'
FAST_HIGHLIGHT_STYLES[unknown-token]='fg=#eba0ac'

# Rainbow brackets — Blue / Mauve / Teal
FAST_HIGHLIGHT_STYLES[bracket-level-1]='fg=#89b4fa,bold'
FAST_HIGHLIGHT_STYLES[bracket-level-2]='fg=#cba6f7,bold'
FAST_HIGHLIGHT_STYLES[bracket-level-3]='fg=#94e2d5,bold'
FAST_HIGHLIGHT_STYLES[paired-bracket]='bg=#585b70'

# Comments — Surface2
FAST_HIGHLIGHT_STYLES[comment]='fg=#585b70'

# Plain text — Text
FAST_HIGHLIGHT_STYLES[default]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[globbing]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[redirection]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[assign]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[variable]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[mathvar]='fg=#cdd6f4'
FAST_HIGHLIGHT_STYLES[mathnum]='fg=#fab387'

# vim: set ft=zsh :
