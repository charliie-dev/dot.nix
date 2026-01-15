{ config, ... }:
{
  git = {
    enable = true;
    ignores = [
      ".env"
      ".DS_Store"
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
        tabwidth = 4;
        autocrlf = false; # set to true if on Windows_NT
      };
      # dont use this, this will cause some cli use ssh over https, but those
      # cli cant communicate w/ ssh-agent, so git ssh auth will fail.
      # url = {
      #   "ssh://git@github.com/" = {
      #     insteadOf = "https://github.com/";
      #   };
      # };
      gpg.ssh = {
        allowedSignersFile = "${config.age.secrets.git_allowed_signers.path}";
      };
      gc = {
        auto = 256;
      };
      pretty = {
        slog = "format:'%C(bold red)%h%Creset %C(bold cyan)<%an>%Creset %C(yellow)%d%Creset %s %Cgreen(%cr)' --abbrev-commit --date=relative";
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
      };
    };
    signing = {
      key = "${config.age.secrets.ssh_ed25519_pub.path}"; # pub key
      signByDefault = true;
      format = "ssh"; # openpgp, ssh, x509
    };
    attributes = [
      "*.pdf diff=pdf"
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
