{
  config,
  pkgs,
  lib,
  ...
}:
let
  nvimdotsUrl = "charliie-dev/nvimdots.lua.git";
  nvimDir = "${config.xdg.configHome}/nvim";
in
{
  # Generate a separate file for the Lua cpath/path. The external Neovim
  # configuration imports this from init.lua, so Home Manager must not replace
  # that entry point or sideload the same Lua through the wrapper.
  xdg.configFile = {
    "nvim/init.lua".enable = lib.mkForce false;
    "nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;
  };

  home.activation.nvimdotsClone = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    httpsUrl="https://github.com/${nvimdotsUrl}"
    sshUrl="git@github.com:${nvimdotsUrl}"

    if [ ! -e "${nvimDir}" ] && [ ! -L "${nvimDir}" ]; then
      run ${pkgs.git}/bin/git clone "$httpsUrl" "${nvimDir}"
    fi

    if [ -L "${nvimDir}" ]; then
      echo "Refusing to manage ${nvimDir}: path is a symlink" >&2
      exit 1
    elif [ -e "${nvimDir}" ]; then
      if [ ! -d "${nvimDir}" ]; then
        echo "Refusing to manage ${nvimDir}: path is not a directory" >&2
        exit 1
      fi

      if ! isWorkTree="$(${pkgs.git}/bin/git -C "${nvimDir}" rev-parse --is-inside-work-tree 2>/dev/null)" \
        || [ "$isWorkTree" != true ]; then
        echo "Refusing to manage ${nvimDir}: path is not a Git worktree" >&2
        exit 1
      fi

      repoTopLevel="$(${pkgs.git}/bin/git -C "${nvimDir}" rev-parse --show-toplevel)"
      repoTopLevel="$(cd "$repoTopLevel" && pwd -P)"
      nvimTopLevel="$(cd "${nvimDir}" && pwd -P)"
      if [ "$repoTopLevel" != "$nvimTopLevel" ]; then
        echo "Refusing to manage ${nvimDir}: Git worktree top-level is $repoTopLevel" >&2
        exit 1
      fi

      if ! originUrls="$(${pkgs.git}/bin/git -C "${nvimDir}" remote get-url --all origin)"; then
        echo "Refusing to manage ${nvimDir}: origin is missing" >&2
        exit 1
      fi
      if [ -z "$originUrls" ]; then
        originUrlCount=0
      else
        originUrlCount="$(printf '%s\n' "$originUrls" | ${pkgs.coreutils}/bin/wc -l)"
      fi
      if [ "$originUrlCount" -ne 1 ]; then
        echo "Refusing to manage ${nvimDir}: origin must have exactly one URL" >&2
        exit 1
      fi

      case "$originUrls" in
        "$httpsUrl")
          run ${pkgs.git}/bin/git -C "${nvimDir}" remote set-url origin "$sshUrl"
          ;;
        "$sshUrl") ;;
        *)
          echo "Refusing to manage ${nvimDir}: origin URL is not an expected nvimdots URL" >&2
          exit 1
          ;;
      esac
    fi
  '';
}
