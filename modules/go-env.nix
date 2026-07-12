# Declaratively manage Go's `env` file — the on-disk target of `go env -w`.
#
# Why not just export GOPATH/GOMODCACHE from zsh? Those exports only exist in an
# interactive zsh, so any `go` invocation OUTSIDE it (GUI IDEs launched from the
# Dock, launchd/cron, tools not managed by home-manager) fell back to the
# default ~/go and rebuilt a module cache there. Go reads THIS file regardless
# of environment variables, so managing it declaratively fixes every context
# with zero env-var dependency — and stays portable across every machine that
# builds this home-manager config.
#
# We deliberately do NOT use `programs.go`: it has no GOMODCACHE option and
# writes its env file to a path Go doesn't read on macOS. Managing the file
# directly gives full control over both the contents and the location.
#
# Location is per-OS because Go resolves it via os.UserConfigDir():
#   - macOS: ~/Library/Application Support/go/env
#   - Linux: $XDG_CONFIG_HOME/go/env  (~/.config/go/env)
# Writing to each OS's default means no GOENV override is needed anywhere.
#
# Values MUST be absolute paths — Go does not expand env vars or ~ in this file.
# NOTE: once this file is a (read-only) nix-store symlink, `go env -w KEY=VAL`
# will fail; add new vars here and re-switch instead.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  goEnv = ''
    GOPATH=${config.xdg.dataHome}/go
    GOMODCACHE=${config.xdg.cacheHome}/go/mod
    GONOPROXY=github.com/nics-dp
    GOPRIVATE=github.com/nics-dp
  '';
in
lib.mkMerge [
  (lib.mkIf pkgs.stdenv.isDarwin {
    home.file."Library/Application Support/go/env".text = goEnv;
  })
  (lib.mkIf pkgs.stdenv.isLinux {
    xdg.configFile."go/env".text = goEnv;
  })
]
