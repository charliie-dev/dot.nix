{
  lazygit = {
    enable = true;
    enableZshIntegration = false; # it will have parsing error when true
    # shellWrapperName = "lg";
    settings = {
      gui = {
        mouseEvents = true;
        language = "en";
        timeFormat = "2022-11-03 15:04"; # https://pkg.go.dev/time#Time.Format
        shortTimeFormat = "15:04";
        showRandomTip = false;
        nerdFontsVersion = "3";
        useHunkModeInStagingView = true;
      };
      git = {
        pagers = [
          {
            pager = "delta --dark --paging=never";
            colorArg = "always";
          }
        ];
        commit = {
          signoff = true;
          autoWrapCommitMessage = true;
          autoWrapWidth = 72;
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
