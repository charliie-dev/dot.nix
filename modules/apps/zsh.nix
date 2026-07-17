{
  config,
  lib,
  pkgs,
  src,
  ...
}:
let
  # macOS Tahoe 26 + nixpkgs zsh 5.9 (built against older Darwin SDK) hangs in
  # `sigsuspend → pause()` waiting for SIGCHLD that never wakes it up — every
  # `$(...)` in zshrc has a chance to deadlock. Apple's `/bin/zsh` (also 5.9,
  # but built with current macOS SDK) works correctly. Until nixpkgs fixes
  # this upstream, point home-manager at system zsh on Darwin.
  # See: zsh Src/signals.c "race prone, or what?" comment.
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
  zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    zprof.enable = false;
    enableCompletion = true;
    completionInit = ''
      autoload -U compinit
      compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
    '';
    enableVteIntegration = if pkgs.stdenv.isDarwin then false else true;
    defaultKeymap = "viins";
    dirHashes = {
      # enter hashdir via `cd ~XXX`
      work = "${config.home.homeDirectory}/Work";
      Work = "${config.home.homeDirectory}/Work";
      ssh = "${config.home.homeDirectory}/.ssh";
      music = "${config.home.homeDirectory}/Music";
      pic = "${config.home.homeDirectory}/Pictures";
      dl = "${config.home.homeDirectory}/Downloads";
      doc = "${config.home.homeDirectory}/Documents";
      cfg = "${config.xdg.configHome}";
      config = "${config.xdg.configHome}";
      share = "${config.xdg.dataHome}";
      state = "${config.xdg.stateHome}";
      cache = "${config.xdg.cacheHome}";
      nvim = "${config.xdg.configHome}/nvim";
      manager = "${config.xdg.configHome}/home-manager";
    };
    # cdpath = [
    #   # autocompletion after `cd`
    #   "${config.xdg.configHome}"
    # ];
    history = {
      path = "${config.xdg.cacheHome}/zsh/history";
      size = 20000; # Set session history size.
      save = 100000; # Set history file size.
      append = false;
      extended = true; # Save timestamp into the history file.
      share = false; # Share command history between zsh sessions
      saveNoDups = true;
      ignoreDups = true;
      ignoreAllDups = true;
      findNoDups = true;
      expireDuplicatesFirst = true;
      ignoreSpace = true; # Do not enter command lines into the history list if the first character is a space.
      # ignorePatterns = [
      #   "rm *"
      #   "pkill *"
      # ];
    };
    setOptions = [
      "NO_beep"
      # ===== History Extra
      # Let histfile managed by system's `fcntl` call to improve better performance and avoid corruption
      "hist_fcntl_lock"
      # Add comamnds as they are typed, don't wait until shell exit
      "inc_append_history"
      # Add EXTENDED_HISTORY format for INC_APPEND_HISTORY
      "inc_append_history_time"
      # Remove extra blanks from each command line being added to history
      "hist_reduce_blanks"
      # Do not execute immediately upon history expansion.
      "hist_verify"
      # Don't beep when accessing non-existent history.
      "NO_hist_beep"
      # ===== Prompt
      # Expand parameters in prompt variables.
      "prompt_subst"
    ];
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins =
        let
          commonPlugins = [
            # lazy-loading `kind:defer`
            "QuarticCat/zsh-smartcache" # better mroth/evalcache
            # "belak/zsh-utils path:completion"
            "Aloxaf/fzf-tab kind:defer"
            "zsh-users/zsh-autosuggestions kind:defer"
            "zdharma-continuum/fast-syntax-highlighting kind:defer" # add before zsh-history-substring-search to prevent breaking
            "zsh-users/zsh-history-substring-search kind:defer"
            "MichaelAquilina/zsh-you-should-use kind:defer"
            # "sunlei/zsh-ssh kind:defer"
          ];
          darwinPlugins =
            if pkgs.stdenv.isDarwin then
              [
                "mattmc3/zephyr path:plugins/homebrew"
                "mattmc3/zephyr path:plugins/macos"
              ]
            else
              [ ];
        in
        commonPlugins ++ darwinPlugins;
    };
    initContent =
      let
        zshDir = "${src}/conf.d/zsh";
        commonFiles = [
          "completion.zsh"
          # "setopt.zsh" # set in nix
          "exports.zsh"
          # "history.zsh" # set in nix
          "functions.zsh"
          "fast-syntax-highlighting.zsh"
          "plugins.zsh"
          "aliases.zsh"
          # "hashdirs.zsh" # set in nix
          "bindkeys.zsh"
        ];
        darwinFiles = if pkgs.stdenv.isDarwin then [ "macos.zsh" ] else [ ];
        readAll = files: builtins.map (f: builtins.readFile "${zshDir}/${f}") files;
      in
      builtins.concatStringsSep "\n" (readAll (commonFiles ++ darwinFiles));
    envExtra = ''
      # Code Agents — 放在 .zshenv 層(envExtra),讓非互動 shell / IDE 內建終端
      # 啟動的 agent 也解析到 XDG 路徑。用 nix 插值展開絕對路徑,不依賴
      # runtime $XDG_CONFIG_HOME(它在互動層 exports.zsh 才設,.zshenv 時尚未存在)。
      # GUI app(ChatGPT.app 的 codex、Aside daemon)另由 launchd brew-env 覆蓋。
      export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude"
      export CODEX_HOME="${config.xdg.configHome}/codex"
      export COPILOT_HOME="${config.xdg.configHome}/copilot"
      export GROK_HOME="${config.xdg.configHome}/grok"
      export MCP_REMOTE_CONFIG_DIR="${config.xdg.dataHome}/mcp-auth"
      export ASIDE_HOME="${config.xdg.dataHome}/aside"
      # grok 隱私釘子(env 優先序高於 config.toml,雙保險)
      export GROK_TELEMETRY_ENABLED=0
      export GROK_FEEDBACK_ENABLED=0
      export GROK_TELEMETRY_TRACE_UPLOAD=0
      export GROK_DISABLE_AUTOUPDATER=1
      # copilot:關連外自動更新(brew cask 管版本);CLI 目前無 telemetry opt-out
      export COPILOT_AUTO_UPDATE=0

      # AWS (non-secret)
      export AWS_DEFAULT_OUTPUT="json"
      export AWS_DATA_PATH="${config.xdg.dataHome}/aws"

      # Completions for stub-packaged tools (mise, …) whose upstream binary is
      # fetched at activation time (see upgradeMise in core.nix). The hook drops
      # _mise here, so it must be on FPATH before compinit runs.
      fpath=("${config.xdg.dataHome}/zsh/site-functions" $fpath)
    '';
    # Doppler secrets loaded by core.nix mkIf enableSecrets
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin { package = systemZsh; };
}
