{
  herdr = {
    enable = true;
    # package 使用預設 pkgs.herdr
    settings = {
      onboarding = false;

      theme = {
        name = "terminal"; # 跟隨 ghostty (固定 Catppuccin Mocha)
        auto_switch = false;
      };

      ui = {
        show_agent_labels_on_pane_borders = true;
        # priority:注意力佇列排序(需要處理的排前面),取代預設的 spaces 分組
        agent_panel_sort = "priority";
        # sidebar 展開列:多加一行任務標題,7 個 session 並行時才分得出誰在做什麼
        sidebar.agents.rows = [
          [
            "state_icon"
            "workspace"
            "tab"
          ]
          [ "terminal_title_stripped" ]
          [ "agent" ]
        ];
        toast = {
          # terminal:走 OSC 9/99 請 ghostty 發桌面通知(可拿到 ghostty 的通知音)
          delivery = "terminal";
          # 延遲送出:到期時 pane 仍是同一狀態才通知,濾掉 subagent 結束造成的瞬間 idle
          delay_seconds = 120;
          # clipboard toast 只吃 top-center / bottom-center,沒有四角
          clipboard.position = "top-center";
        };
        # 背景 workspace 的 agent 狀態音效
        sound.enabled = true;
      };

      experimental = {
        pane_history = true;
        switch_ascii_input_source_in_prefix = true;
        # 把 focused pane 的 cursor 露給 ghostty,讓 IME 候選字視窗跟得上
        # 自繪 cursor 的 TUI(claude/codex/pi)
        reveal_hidden_cursor_for_cjk_ime = true;
        cjk_ime_agents = [
          "claude"
          "codex"
          "grok"
          "pi"
        ];
        # 本地 Kitty graphics 渲染;需外層終端支援(ghostty 有)
        kitty_graphics = true;
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

        # detach:預設 prefix+q 會撞 close_pane,移到 prefix+d 對齊 tmux
        detach = "prefix+d";

        # close
        close_pane = "prefix+q";
        close_tab = "prefix+shift+q";

        # tab
        new_tab = "prefix+t";
        next_tab = "prefix+]";
        previous_tab = "prefix+[";
        switch_tab = "prefix+1..9";

        # herdr 招牌
        # 預設 prefix+o 會撞 open_worktree,改到空出來的 prefix+n
        open_notification_target = "prefix+n";
        toggle_sidebar = "prefix+b";
        new_worktree = "prefix+w";
        open_worktree = "prefix+o";
        focus_agent = "prefix+alt+1..9";

        # popup:session-modal 終端,不動 tab layout(prefix+g 已被 goto 佔用)
        command = [
          {
            key = "prefix+alt+g";
            type = "popup";
            command = "lazygit";
            width = "80%";
            height = "80%";
          }
          {
            key = "prefix+alt+d";
            type = "popup";
            command = "lazydocker";
            width = "80%";
            height = "80%";
          }
        ];
      };

      worktrees.directory = "~/Work/herdr/worktrees";
    };
  };
}
