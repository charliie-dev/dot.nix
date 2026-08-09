{
  lazygit = {
    enable = true;
    enableZshIntegration = false; # custom `lg` alias lives in modules/apps/zsh/aliases.nix
    # shellWrapperName = "lg";
    settings = {
      gui = {
        language = "en";
        timeFormat = "2006-01-02 15:04"; # https://pkg.go.dev/time#Time.Format
        shortTimeFormat = "15:04";
        showRandomTip = false;
        nerdFontsVersion = "3";
      };
      git = {
        diffRenderers = [
          {
            command = "delta --dark --paging=never";
            colorArg = "always";
          }
        ];
        commit = {
          signOff = true;
          autoWrapCommitMessage = true;
        };
        parseEmoji = true;
      };
      update = {
        method = "never";
      };
      refresher = {
        fetchInterval = 600;
      };
      os = {
        openDirInEditor = "nvim";
        editPreset = "nvim";
      };
      notARepository = "skip"; # one of: 'prompt' | 'create' | 'skip' | 'quit'
      promptToReturnFromSubprocess = false;
    };
  };
}
