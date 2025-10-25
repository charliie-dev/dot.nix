{
  asciinema = {
    enable = true;
    settings = {
      session = {
        capture_input = true;
        capture_env = "SHELL,TERM,USER";
        prefix_key = "^a";
        pause_key = "^p";
        add_marker_key = "^x";
      };
      playback = {
        pause_key = "p";
        step_key = "s";
        next_marker_key = "m";
      };
      notifications = {
        enabled = false;
        command = "tmux display-message \"$TEXT\"";
      };
      # server = {
      #   url = "https://asciinema.example.com";
      # };
    };
  };
}
