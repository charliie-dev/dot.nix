{
  config,
  pkgs,
  src,
  ...
}:
let
  exportSecret =
    { secret, env }:
    ''
      if [ -r ${config.age.secrets.${secret}.path} ]; then
        export ${env}="$(tr -d '\r\n' < ${config.age.secrets.${secret}.path})"
      fi
    '';
  exportSecrets = secrets: builtins.concatStringsSep "\n" (map exportSecret secrets);
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
            # "Aloxaf/fzf-tab kind:defer" # needs to load after `compinit`, but before wrap widgets, such as `zsh-autosuggestions` or `fast-syntax-highlighting`
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
      # Azure
      ${exportSecrets [
        {
          secret = "azure_openai_api_endpoint";
          env = "AZURE_OPENAI_API_ENDPOINT";
        }
        {
          secret = "azure_openai_api_key";
          env = "AZURE_OPENAI_API_KEY";
        }
        {
          secret = "azure_openai_api_version";
          env = "AZURE_OPENAI_API_VERSION";
        }
      ]}

      # AWS
      export AWS_DEFAULT_OUTPUT="json"
      export AWS_DATA_PATH="${config.xdg.dataHome}/aws"
      ${exportSecrets [
        {
          secret = "aws_region";
          env = "AWS_REGION";
        }
        {
          secret = "aws_access_key_id";
          env = "AWS_ACCESS_KEY_ID";
        }
        {
          secret = "aws_secret_access_key";
          env = "AWS_SECRET_ACCESS_KEY";
        }
      ]}

      # D2 Studio
      ${exportSecret {
        secret = "d2_token";
        env = "TSTRUCT_TOKEN";
      }}
    '';
  };
}
