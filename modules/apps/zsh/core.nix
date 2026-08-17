{
  config,
  lib,
  pkgs,
  ...
}:
let
  # macOS Tahoe 26 + nixpkgs zsh 5.9 (built against an older Darwin SDK)
  # can hang in sigsuspend/pause while waiting for SIGCHLD. Apple's /bin/zsh
  # is built against the current SDK, so use it until nixpkgs catches up.
  systemZsh = pkgs.runCommand "system-zsh" { meta.mainProgram = "zsh"; } ''
    mkdir -p $out/bin
    ln -sf /bin/zsh $out/bin/zsh
    if [ -d /usr/share/zsh ]; then
      mkdir -p $out/share
      ln -sf /usr/share/zsh $out/share/zsh
    fi
  '';
in
{
  enable = true;
  dotDir = "${config.xdg.configHome}/zsh";
  zprof.enable = false;
  enableCompletion = true;
  completionInit = ''
    autoload -U compinit
    compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
  '';
  enableVteIntegration = !pkgs.stdenv.hostPlatform.isDarwin;
  defaultKeymap = "viins";

  dirHashes = {
    # Enter a hashdir via `cd ~XXX`.
    work = "${config.home.homeDirectory}/Work";
    Work = "${config.home.homeDirectory}/Work";
    ssh = "${config.home.homeDirectory}/.ssh";
    music = "${config.home.homeDirectory}/Music";
    pic = "${config.home.homeDirectory}/Pictures";
    dl = "${config.home.homeDirectory}/Downloads";
    doc = "${config.home.homeDirectory}/Documents";
    cfg = config.xdg.configHome;
    config = config.xdg.configHome;
    share = config.xdg.dataHome;
    state = config.xdg.stateHome;
    cache = config.xdg.cacheHome;
    nvim = "${config.xdg.configHome}/nvim";
    manager = "${config.xdg.configHome}/home-manager";
  };

  # Exported only for zsh sessions. Cross-shell variables belong in
  # home.sessionVariables in modules/core.nix.
  sessionVariables = {
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
    PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonrc";
    PSQL_HISTORY = "${config.xdg.stateHome}/psql_history";
    LC_COLLATE = "C";
  };

  # Plugin state does not need to leak into child-process environments.
  localVariables = {
    ZSH_SMARTCACHE_DIR = "${config.xdg.cacheHome}/zsh/smartcache";
  };

  history = {
    path = "${config.xdg.stateHome}/zsh/history";
    size = 120000;
    save = 100000;
    append = false;
    extended = true;
    share = false;
    saveNoDups = true;
    ignoreDups = true;
    ignoreAllDups = true;
    findNoDups = true;
    expireDuplicatesFirst = true;
    ignoreSpace = true;
  };

  setOptions = [
    "NO_beep"
    "inc_append_history_time"
    "hist_reduce_blanks"
    "hist_verify"
    "NO_hist_beep"
    "prompt_subst"
  ];

  envExtra = ''
    # PAM/systemd normally supplies XDG_RUNTIME_DIR on Linux. macOS has no
    # equivalent, so use its per-user TMPDIR without overriding a real value.
    if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]; then
      if [[ "$OSTYPE" == darwin* ]]; then
        export XDG_RUNTIME_DIR="''${TMPDIR%/}"
      else
        export XDG_RUNTIME_DIR="/run/user/$UID"
      fi
    fi

    # secureSocket may compute TMUX_TMPDIR before the macOS fallback above.
    if [[ "$OSTYPE" == darwin* && "''${TMUX_TMPDIR:-}" == /run/user/* ]]; then
      export TMUX_TMPDIR="$XDG_RUNTIME_DIR"
    fi

    # Completion functions generated for activation-managed binaries such as
    # mise must be available before compinit runs.
    fpath=("${config.xdg.dataHome}/zsh/site-functions" $fpath)
  '';
}
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { package = systemZsh; }
