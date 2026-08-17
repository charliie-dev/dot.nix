{ lib, pkgs, ... }:
let
  pluginSpecs = [
    # zsh-smartcache must be available before integrations.nix runs.
    { repo = "QuarticCat/zsh-smartcache"; }
    # Deferred plugins run FIFO after .zshrc has completed.
    {
      repo = "Aloxaf/fzf-tab";
      kind = "defer";
    }
    # Syntax highlighting is zsh-patina (modules/apps/patina.nix), which
    # loads at order 545 so it is in place before this plugin list.
    {
      repo = "zsh-users/zsh-autosuggestions";
      kind = "defer";
    }
    {
      repo = "zsh-users/zsh-history-substring-search";
      kind = "defer";
    }
    {
      repo = "MichaelAquilina/zsh-you-should-use";
      kind = "defer";
    }
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    {
      repo = "mattmc3/zephyr";
      path = "plugins/homebrew";
    }
    {
      repo = "mattmc3/zephyr";
      path = "plugins/macos";
    }
  ];
  renderedPlugins = import ./antidote-bundle.nix pluginSpecs;
  bundleBytes = builtins.concatStringsSep "\n" renderedPlugins + "\n";
  loaderSettings = {
    antidoteSource = "${pkgs.antidote}/share/antidote/antidote.zsh";
    homeDirectory = "\${XDG_CACHE_HOME:-$HOME/.cache}/antidote";
    mkdir = "${pkgs.coreutils}/bin/mkdir";
    staticDirectory = "home-manager";
    staticNamePrefix = "home-manager-";
    staticNameSuffix = ".zsh";
    useFriendlyNames = true;
  };
  bundleHash = builtins.substring 0 12 (
    builtins.hashString "sha256" (
      builtins.toJSON {
        inherit bundleBytes loaderSettings;
      }
    )
  );
  bundleFile = pkgs.writeText "home-manager-antidote-bundle-${bundleHash}" bundleBytes;
in
{
  antidote = {
    enable = false;
    package = pkgs.antidote;
    plugins = renderedPlugins;
    inherit (loaderSettings) useFriendlyNames;
  };

  initContent = lib.mkOrder 550 ''
    ## home-manager/antidote begin
    source ${lib.escapeShellArg loaderSettings.antidoteSource}
    zstyle ':antidote:bundle' use-friendly-names 'yes'

    _hm_antidote_bundle=${lib.escapeShellArg bundleFile}
    zstyle ':antidote:bundle' file "$_hm_antidote_bundle"
    zstyle ':antidote:home' dir "${loaderSettings.homeDirectory}"
    _hm_antidote_home="$(antidote home)"
    _hm_antidote_umask="$(umask)"
    _hm_antidote_ready=1
    umask 077

    _hm_antidote_safe_dir() {
      local path="$1" private="$2"
      local -A _hm_antidote_info
      [[ ! -L "$path" && -d "$path" ]] || return 1
      zstat -H _hm_antidote_info -- "$path" 2>/dev/null || return 1
      (( (_hm_antidote_info[mode] & 8#170000) == 8#040000 \
        && _hm_antidote_info[uid] == EUID \
        && (_hm_antidote_info[mode] & 8#022) == 0 )) || return 1
      [[ "$private" != private ]] && return 0
      (( (_hm_antidote_info[mode] & 8#777) == 8#700 ))
    }

    _hm_antidote_safe_file() {
      local path="$1"
      local -A _hm_antidote_info
      [[ ! -e "$path" && ! -L "$path" ]] && return 0
      [[ ! -L "$path" ]] || return 1
      zstat -H _hm_antidote_info -- "$path" 2>/dev/null || return 1
      (( (_hm_antidote_info[mode] & 8#170000) == 8#100000 \
        && _hm_antidote_info[uid] == EUID \
        && (_hm_antidote_info[mode] & 8#022) == 0 \
        && _hm_antidote_info[nlink] == 1 ))
    }

    if ! zmodload zsh/stat; then
      print -ru2 -- "home-manager antidote: refusing unavailable zsh/stat"
      _hm_antidote_ready=0
    elif [[ "$_hm_antidote_home" != /* \
      || "$_hm_antidote_home" == *$'\n'* \
      || "$_hm_antidote_home" == *$'\r'* ]]; then
      print -ru2 -- "home-manager antidote: refusing invalid antidote home"
      _hm_antidote_ready=0
    elif [[ ! -e "$_hm_antidote_home" && ! -L "$_hm_antidote_home" ]]; then
      if ! ${lib.escapeShellArg loaderSettings.mkdir} -p -- "$_hm_antidote_home"; then
        print -ru2 -- "home-manager antidote: refusing unsafe antidote home: $_hm_antidote_home"
        _hm_antidote_ready=0
      fi
    fi

    if (( _hm_antidote_ready )) \
      && ! _hm_antidote_safe_dir "$_hm_antidote_home" root; then
      print -ru2 -- "home-manager antidote: refusing unsafe antidote home: $_hm_antidote_home"
      _hm_antidote_ready=0
    fi

    if (( _hm_antidote_ready )); then
      _hm_antidote_static_dir="$_hm_antidote_home/${loaderSettings.staticDirectory}"
      ${lib.escapeShellArg loaderSettings.mkdir} -p -m 0700 -- "$_hm_antidote_static_dir" 2>/dev/null || true
      if ! _hm_antidote_safe_dir "$_hm_antidote_static_dir" private; then
        print -ru2 -- "home-manager antidote: refusing unsafe static directory: $_hm_antidote_static_dir"
        _hm_antidote_ready=0
      fi
    fi

    if (( _hm_antidote_ready )); then
      _hm_antidote_static="$_hm_antidote_static_dir/${loaderSettings.staticNamePrefix}${bundleHash}${loaderSettings.staticNameSuffix}"
      _hm_antidote_sidecar="$_hm_antidote_static.zwc"
      if ! _hm_antidote_safe_file "$_hm_antidote_static"; then
        print -ru2 -- "home-manager antidote: refusing unsafe static file: $_hm_antidote_static"
      elif ! _hm_antidote_safe_file "$_hm_antidote_sidecar"; then
        print -ru2 -- "home-manager antidote: refusing unsafe static sidecar: $_hm_antidote_sidecar"
      else
        zstyle ':antidote:static' file "$_hm_antidote_static"
        antidote load "$_hm_antidote_bundle" "$_hm_antidote_static"
      fi
    fi

    umask "$_hm_antidote_umask"
    unfunction _hm_antidote_safe_dir _hm_antidote_safe_file
    unset _hm_antidote_bundle _hm_antidote_home _hm_antidote_ready
    unset _hm_antidote_sidecar _hm_antidote_static _hm_antidote_static_dir _hm_antidote_umask
    ## home-manager/antidote end
  '';
}
