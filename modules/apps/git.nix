{
  git = {
    enable = true;
    userName = "charliie-dev";
    userEmail = "mail@charliie.dev";
    ignores = [
      "*/.env"
      "./.DS_Store"
    ];
    aliases = {
      st = "status";
      cm = "commit -m";
      co = "checkout";
      br = "branch";
      sw = "switch";
      lo = "log --oneline --graph";
      ls = "log --graph --pretty=slog";
      l1 = "log -1 --pretty=slog";
      rh = "reset --hard origin/main";
      rp = "remote prune origin";
      lrh = "ls-remote --heads";
      lrt = "ls-remote --tags";
      amend = "commit --amend"; # amend last commit
      dlc = "diff --cached HEAD^"; # check the diff on last commit
      alias = "config --get-regexp alias";
      structure = "log --oneline --simplify-by-decoration --graph --all";
      remoteurl = "remote get-url origin";
      ignore = "update-index --skip-worktree";
      unignore = "update-index --no-skip-worktree";
      ignorels = "!git ls-files -v | grep \"^S\"";
    };
    extraConfig = {
      init = {
        defaultBranch = "main";
      };
      core = {
        preloadindex = true;
        fscache = true;
      };
      pretty = {
        slog = "format:'%C(bold red)%h%Creset %C(bold cyan)<%an>%Creset %C(yellow)%d%Creset %s %Cgreen(%cr)' --abbrev-commit --date=relative";
      };
      merge = {
        conflictstyle = "zdiff3";
      };
      pager = {
        difftool = true;
      };
      diff = {
        colorMoved = "default";
      };
    };
    # Syntax-highlighting pager for git
    delta = {
      enable = true;
      options = {
        navigate = true; # use n and N to move between diff sections
        dark = true;
        line-numbers = true;
        side-by-side = true;
        whitespace-error-style = "22 reverse";
      };
    };
    # Syntax-aware diff
    difftastic = {
      enable = false;
      enableAsDifftool = true;
      options = {
        color = "always";
        background = "dark";
        display = "side-by-side"; # "side-by-side", "side-by-side-show-both", "inline"
      };
    };
    # Git extension for versioning large files
    lfs = {
      enable = true;
      skipSmudge = false;
    };
  };
}
