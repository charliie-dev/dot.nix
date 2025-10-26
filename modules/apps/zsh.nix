{
  config,
  pkgs,
  src,
  ...
}:
{
  zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    zprof.enable = false;
    enableCompletion = false;
    enableVteIntegration = if pkgs.stdenv.isDarwin then false else true;
    defaultKeymap = "viins";
    antidote = {
      enable = true;
      useFriendlyNames = true;
      plugins = [
        # lazy-loading `kind:defer`
        "QuarticCat/zsh-smartcache" # better mroth/evalcache
        "zsh-users/zsh-completions kind:fpath"
        "belak/zsh-utils path:completion"
        # "Aloxaf/fzf-tab kind:defer" # needs to load after `compinit`, but before wrap widgets, such as `zsh-autosuggestions` or `fast-syntax-highlighting`
        "zsh-users/zsh-autosuggestions kind:defer"
        "zdharma-continuum/fast-syntax-highlighting kind:defer" # add before zsh-history-substring-search to prevent breaking
        "zpm-zsh/colorize kind:defer" # Colorize the output of various programs
        "zpm-zsh/colors" # Enhanced colors for zsh
        "Freed-Wu/zsh-help" # colorize `XXX --help`
        "zsh-users/zsh-history-substring-search kind:defer"
        "MichaelAquilina/zsh-you-should-use kind:defer"
        # "MichaelAquilina/zsh-autoswitch-virtualenv kind:defer" # Auto-switch python venv, pipenv, poetry
        "sunlei/zsh-ssh kind:defer"
      ];
    };
    initContent =
      let
        zshDir = "${src}/conf.d/zsh";
        commonFiles = [
          "completion.zsh"
          "setopt.zsh"
          "exports.zsh"
          "history.zsh"
          "functions.zsh"
          "bindkeys.zsh"
          "plugins.zsh"
          "aliases.zsh"
          "hashdirs.zsh"
        ];
        darwinFiles = if pkgs.stdenv.isDarwin then [ "macos.zsh" ] else [ ];
        readAll = files: builtins.map (f: builtins.readFile "${zshDir}/${f}") files;
      in
      builtins.concatStringsSep "\n" (readAll (commonFiles ++ darwinFiles));
    envExtra = ''
      # Azure
      if [ -r ${config.age.secrets.azure_openai_api_endpoint.path} ]; then
        export AZURE_OPENAI_API_ENDPOINT="$(tr -d '\r\n' < ${config.age.secrets.azure_openai_api_endpoint.path})"
      fi
      if [ -r ${config.age.secrets.azure_openai_api_key.path} ]; then
        export AZURE_OPENAI_API_KEY="$(tr -d '\r\n' < ${config.age.secrets.azure_openai_api_key.path})"
      fi
      if [ -r ${config.age.secrets.azure_openai_api_version.path} ]; then
        export AZURE_OPENAI_API_VERSION="$(tr -d '\r\n' < ${config.age.secrets.azure_openai_api_version.path})"
      fi

      # AWS
      export AWS_DEFAULT_OUTPUT="json"
      export AWS_DATA_PATH="${config.xdg.dataHome}/aws"
      if [ -r ${config.age.secrets.aws_region.path} ]; then
        export AWS_REGION="$(tr -d '\r\n' < ${config.age.secrets.aws_region.path})"
      fi
      if [ -r ${config.age.secrets.aws_access_key_id.path} ]; then
        export AWS_ACCESS_KEY_ID="$(tr -d '\r\n' < ${config.age.secrets.aws_access_key_id.path})"
      fi
      if [ -r ${config.age.secrets.aws_secret_access_key.path} ]; then
        export AWS_SECRET_ACCESS_KEY="$(tr -d '\r\n' < ${config.age.secrets.aws_secret_access_key.path})"
      fi
    '';
  };
}
