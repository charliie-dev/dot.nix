{ config, lib, ... }:
{
  starship = {
    enable = true;
    configPath = "${config.xdg.configHome}/starship/starship.toml";
    enableZshIntegration = false; # self-definded smartcache in conf.d/zsh
    enableIonIntegration = false;
    settings = {
      add_newline = true;
      scan_timeout = 100;
      command_timeout = 1000;
      continuation_prompt = "[  ❯ ](fg:green)";

      format = lib.concatStrings [
        "[](fg:surface0)"
        "$os"
        "$hostname"
        "$directory"
        # "\${custom.git_remote}"
        "$git_branch"
        "\${custom.git_worktree}"
        "$git_status"
        "$git_metrics"
        "[](surface0)"

        "$line_break"
        "  "
        # "$shell"
        "$character"
      ];

      right_format = lib.concatStrings [
        "[](fg:surface0)"
        "$gcloud"
        "$aws"
        "$azure"
        "$mise"
        "$cmd_duration"
        # "$all"
        "[](surface0)"
      ];

      # ==============================================================================
      #  RHS-1
      # ==============================================================================
      # Shows an icon that should be included by zshrc script based on the distribution or os
      os = {
        disabled = false;
        style = "fg:subtext1 bg:surface0";
        format = "[$symbol]($style)";
        symbols = {
          AIX = "➿ ";
          ALTLinux = "Ⓐ ";
          AOSC = " ";
          AlmaLinux = " ";
          Alpaquita = " ";
          Alpine = " ";
          Amazon = " ";
          Android = " ";
          Arch = " ";
          Artix = " ";
          Bluefin = "󰈺 ";
          CachyOS = "🎗️ ";
          CentOS = " ";
          Debian = " ";
          DragonFly = " ";
          Elementary = " ";
          Emscripten = " ";
          EndeavourOS = " ";
          Fedora = " ";
          FreeBSD = " ";
          Garuda = "󰛓 ";
          Gentoo = " ";
          HardenedBSD = "󰞌 ";
          Illumos = " ";
          InstantOS = "⏲️ ";
          Ios = "󰀷 ";
          Kali = " ";
          Linux = " ";
          Mabox = " ";
          Macos = " ";
          Manjaro = " ";
          Mariner = " ";
          MidnightBSD = " ";
          Mint = "󰣭 ";
          NetBSD = " ";
          NixOS = " ";
          Nobara = " ";
          OpenBSD = " ";
          OpenCloudOS = "☁️ ";
          OracleLinux = "󰌷 ";
          PikaOS = "🐤 ";
          Pop = " ";
          Raspbian = " ";
          RedHatEnterprise = "󱄛 ";
          Redhat = "󱄛 ";
          Redox = "󰀘 ";
          RockyLinux = " ";
          SUSE = " ";
          Solus = " ";
          Ubuntu = " ";
          Ultramarine = "🔷 ";
          Unknown = " ";
          Uos = "🐲 ";
          Void = " ";
          Windows = " ";
          Zorin = " ";
          openEuler = "🦉 ";
          openSUSE = " ";
        };
      };

      hostname = {
        disabled = false;
        ssh_only = true;
        style = "fg:sky bg:surface0";
        format = "[ · ](bg:surface0)[$hostname]($style)";
        # trim_at = ".com"
      };

      directory = {
        before_repo_root_style = "fg:subtext0 bg:surface0";
        repo_root_style = "fg:flamingo bg:surface0";
        read_only_style = "fg:red bg:surface0";
        style = "fg:subtext0 bg:surface0";
        repo_root_format = "[ · ](bg:surface0)[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style)";
        format = "[ $read_only]($read_only_style)[$path]($style)";
        home_symbol = " ~";
        read_only = " ";
        truncation_length = 4;
        substitutions = {
          "Documents" = "󰈙 ";
          "Downloads" = " ";
          "Movies" = " ";
          "Music" = "󰝚 ";
          "Pictures" = " ";
          "Work" = " ";
        };
        use_os_path_sep = false;
      };

      # custom.git_remote = {
      #   description = "Display remote Git server icon.";
      #   when = "git rev-parse --is-inside-work-tree 2> /dev/null";
      #   format = "[ · ](bg:surface0)[$output]($style)";
      #   style = "bg:surface0";
      #   command = ''
      #     GIT_REMOTE=$(command git ls-remote --get-url 2> /dev/null)
      #     if [[ "''$GIT_REMOTE" =~ "github" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     elif [[ "''$GIT_REMOTE" =~ "gitlab" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     elif [[ "''$GIT_REMOTE" =~ "bitbucket" ]]; then
      #         GIT_REMOTE_SYMBOL="󰂨 "
      #     elif [[ "''$GIT_REMOTE" =~ "codeberg" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     elif [[ "''$GIT_REMOTE" =~ "dev.azure.com" ]] || [[ "''$GIT_REMOTE" =~ "visualstudio.com" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     elif [[ "''$GIT_REMOTE" =~ "gitea" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     elif [[ "''$GIT_REMOTE" =~ "forgejo" ]]; then
      #         GIT_REMOTE_SYMBOL=" "
      #     else
      #         GIT_REMOTE_SYMBOL=" "
      #     fi
      #     echo "''$GIT_REMOTE_SYMBOL"
      #   '';
      #   require_repo = true;
      #   ignore_timeout = true;
      # };

      git_branch = {
        symbol = " ";
        style = "fg:mauve bg:surface0";
        format = "[ · ](bg:surface0)[$symbol$branch]($style)";
      };

      custom.git_worktree = {
        description = "Show indicator when inside a git worktree";
        format = "[ · ](bg:surface0)[$symbol]($style)";
        style = "bold fg:green bg:surface0";
        symbol = "󱘎 ";
        when = ''[ "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" ]'';
        require_repo = true;
        ignore_timeout = true;
      };

      git_status = {
        format = "([ · ](bg:surface0)[$all_status$ahead_behind]($style))";
        style = "fg:yellow bg:surface0";
        ignore_submodules = false;
        # options available for format
        conflicted = "[ ](bold fg:red bg:surface0)";
        deleted = "[ ](fg:red bg:surface0)";
        modified = "[ ](fg:yellow bg:surface0)";
        renamed = "[ ](fg:blue bg:surface0)";
        staged = "[ ](fg:green bg:surface0)";
        stashed = "[󱧕 ](fg:lavender bg:surface0)";
        typechanged = "[ ](fg:maroon bg:surface0)";
        untracked = "[ ](fg:sapphire bg:surface0)";

        ahead = "[⇡\${count}](fg:teal bg:surface0)";
        behind = "[⇣\${count}](fg:peach bg:surface0)";
        diverged = "[ ⇡\${ahead_count}⇣\${behind_count}](fg:mauve bg:surface0)";
      };

      git_metrics = {
        disabled = false;
        added_style = "fg:green bg:surface0";
        deleted_style = "fg:red bg:surface0";
        format = "[ · ](bg:surface0)[+$added]($added_style)[/](fg:text bg:surface0)[-$deleted]($deleted_style)";
      };

      # ==============================================================================
      #  RHS-2
      # ==============================================================================
      character = {
        disabled = false;
        success_symbol = "[❯](bold fg:green)";
        error_symbol = "[❯](bold fg:red)";
        vimcmd_symbol = "[❮](bold fg:yellow)";
      };

      # ==============================================================================
      #  LHS
      # ==============================================================================
      gcloud = {
        disabled = false;
        symbol = "󱇶 ";
        style = "bg:surface0";
        format = "[$symbol($project)]($style)";
        project_aliases = {
          "nics-data-confluence" = "DCF";
        };
      };

      aws = {
        disabled = false;
        symbol = "󰸏 ";
        # format = "[\$symbol(\$profile)(\\(\$region\\) )](\$style)";
        style = "bg:surface0";
        format = "[ · ](bg:surface0)[\$symbol(\$profile)](\$style)";
        profile_aliases = {
          "default" = "NICS";
        };
      };

      azure = {
        disabled = false;
        symbol = "󰠅 ";
        style = "bg:surface0";
        format = "[ · ](bg:surface0)[$symbol($subscription)]($style)";
        subscription_aliases = {
          "Azure_nics2" = "NICS";
        };
      };

      mise = {
        disabled = false;
        symbol = "󰭼 ";
        style = "fg:pink bg:surface0";
        healthy_symbol = " ";
        unhealthy_symbol = " ";
        format = "[ · ](bg:surface0)[$symbol$health]($style)";
      };

      cmd_duration = {
        min_time = 10;
        style = "fg:flamingo bg:surface0";
        format = "[ · ](bg:surface0)[󰔟 $duration]($style)";
      };

      # ==============================================================================
      # Archive
      # ==============================================================================
      docker_context = {
        disabled = true;
        symbol = " ";
        style = "bg:surface0";
        format = "[$symbol$context]($style)";
      };

      python = {
        disabled = true;
        style = "yellow bold";
        format = "[\${symbol}\${pyenv_prefix}(\${version})(\($virtualenv\))]($style)";
        version_format = "v\${raw}";
        symbol = "󰌠 ";
      };

      conda = {
        disabled = true;
        style = "dimmed green";
        format = "[$symbol$environment]($style) ";
        symbol = " ";
        truncation_length = 1;
        ignore_base = false;
      };

      shell = {
        disabled = true;
        fish_indicator = "󰈺";
        powershell_indicator = "";
        cmd_indicator = "";
        zsh_indicator = "󰰸";
        bash_indicator = "";
        unknown_indicator = "?";
        style = "teal";
      };
    };
  };
}
