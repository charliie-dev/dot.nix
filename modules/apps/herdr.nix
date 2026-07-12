{
  herdr = {
    enable = true;
    # package 使用預設 pkgs.herdr (0.7.3)
    settings = {
      onboarding = false;

      theme = {
        name = "terminal"; # 跟隨 ghostty (固定 Catppuccin Mocha)
        auto_switch = false;
      };

      ui = {
        show_agent_labels_on_pane_borders = true;
        toast.delivery = "terminal";
      };

      experimental = {
        pane_history = true;
        switch_ascii_input_source_in_prefix = true;
      };

      keys = {
        prefix = "ctrl+a";

        # split (對齊 ghostty \ 和 -)
        split_vertical = "prefix+\\";
        split_horizontal = "prefix+minus";

        # pane 導航 (hjkl)
        focus_pane_left = "prefix+h";
        focus_pane_down = "prefix+j";
        focus_pane_up = "prefix+k";
        focus_pane_right = "prefix+l";

        # zoom:放大當前 pane 至佔滿同 tab(需 tab 內 ≥2 pane 才有效果,單一 pane 為 no-op)
        zoom = "prefix+z";

        # close
        close_pane = "prefix+q";
        close_tab = "prefix+shift+q";

        # tab
        new_tab = "prefix+t";
        next_tab = "prefix+]";
        previous_tab = "prefix+[";
        switch_tab = "prefix+1..9";

        # herdr 招牌
        toggle_sidebar = "prefix+b";
        new_worktree = "prefix+w";
        open_worktree = "prefix+o";
        focus_agent = "prefix+alt+1..9";
      };
    };
  };
}
