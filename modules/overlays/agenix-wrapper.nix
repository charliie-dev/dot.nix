# Wrapper overlay for agenix to filter out Determinate Nix warnings
# about unknown settings (eval-cores, lazy-trees)
{ agenix }:
_final: prev: {
  agenix = prev.writeShellScriptBin "agenix" ''
    AGENIX_BIN="${agenix.packages.${prev.stdenv.hostPlatform.system}.default}/bin/agenix"

    # Check if -e (edit) flag is present - needs direct terminal access
    EDIT_MODE=false
    for arg in "$@"; do
      [[ "$arg" == "-e" || "$arg" == "--edit" ]] && EDIT_MODE=true && break
    done

    if $EDIT_MODE; then
      # Edit mode: run directly to preserve terminal/editor interaction
      # Warnings will appear but no terminal corruption
      exec "$AGENIX_BIN" "$@"
    else
      # Non-edit mode: filter warnings using temp file
      TMPFILE=$(mktemp)
      trap 'rm -f "$TMPFILE"' EXIT
      "$AGENIX_BIN" "$@" 2>"$TMPFILE"
      RET=$?
      grep -v "warning: unknown setting" "$TMPFILE" >&2
      exit $RET
    fi
  '';
}
