{
  fzf = {
    enable = true;
    # enableZshIntegration = true;
    # defaultCommand = ""
    defaultOptions = [
      "--reverse --margin=3% --style=full"
      "--border=rounded"
      "--prompt='$ > '"
      "--input-border"
      "--input-label=' Input '"
      "--header-border"
      # "--header-label=' File Type '"
      "--list-border --multi --highlight-line --gap --pointer='>'"
      "--preview-border"
      "--preview='pistol {}'"
      "--bind 'focus:transform-preview-label:[ -n {} ] && printf \\\" Previewing [{}] \\\"'"
      # "--bind 'focus:+transform-header:file --brief {} || echo \\\" No file selected \\\"'"
    ];
    colors = {
      border = "#ca9ee6";
      label = "#cba6f7";
      preview-border = "#f2d5cf";
      preview-label = "#f5e0dc";
      list-border = "#81c8be";
      list-label = "#94e2d5";
      input-border = "#ea999c";
      input-label = "#eba0ac";
      header-border = "#85c1dc";
      header-label = "#74c7ec";
      info = "#cba6f7";
      pointer = "#f5e0dc";
      spinner = "#f5e0dc";
      hl = "#f38ba8";
      marker = "#b4befe";
      "fg+" = "#cdd6f4";
      prompt = "#cba6f7";
      "hl+" = "#f38ba8";
      selected-bg = "#45475a";
    };
    changeDirWidgetCommand = "fd --type d"; # ALT-C
    fileWidgetCommand = "fd --type f"; # CTRL-T
    # CTRL-R
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
    tmux = {
      enableShellIntegration = true;
      shellIntegrationOptions = [ "-d 60%" ];
    };
  };

}
