_: {
  git = {
    enable = true;
    ignores = [
      ".env"
      ".DS_Store"
      ".codegraph/"
    ];
    settings = {
      user = {
        name = "charliie-dev";
        email = "mail@charliie.dev";
      };
      init = {
        defaultBranch = "main";
      };
      core = {
        fsmonitor = false;
        untrackedcache = true;
        # fscache = true; # speed up git on Windows_NT
        # preloadindex = true; # speed up git on Windows_NT
        whitespace = "blank-at-eol,blank-at-eof,space-before-tab,tabwidth=4";
        autocrlf = false; # set to true if on Windows_NT
      };
      # Go discovers private GitHub modules through HTTPS. Rewrite only the
      # private organization so unrelated GitHub tools keep using HTTPS.
      url = {
        "ssh://git@github.com/nics-dp/" = {
          insteadOf = "https://github.com/nics-dp/";
        };
      };
      gpg.ssh = { };
      gc = {
        auto = 256;
      };
      pretty = {
        slog = "format:%C(bold red)%h%Creset %C(bold cyan)<%an>%Creset %C(yellow)%d%Creset %s %Cgreen(%cr)";
      };
      merge = {
        tool = "nvimdiff3";
        conflictstyle = "zdiff3";
      };
      pager = {
        difftool = true;
      };
      diff = {
        colorMoved = "default";
      };
      alias = {
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
        sweep = "!bash ~/.local/bin/git-sweep";
        gone = "!bash ~/.local/bin/git-sweep --dry-run";
      };
    };
    signing = {
      signByDefault = true;
      format = "ssh"; # openpgp, ssh, x509
    };
    includes = [
      {
        condition = "hasconfig:remote.*.url:git@github.com:nics-dp/**";
        path = "~/.config/git/config-work";
      }
      {
        condition = "hasconfig:remote.*.url:git@github.com:nics-tw/**";
        path = "~/.config/git/config-work";
      }
    ];
    # Git extension for versioning large files
    lfs = {
      enable = true;
      skipSmudge = false;
    };
    maintenance = {
      enable = true;
      repositories = [
        "~/.config/home-manager"
        "~/.config/nvim"
      ];
    };
  };
}
