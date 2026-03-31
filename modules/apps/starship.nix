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

      format = lib.concatStrings [
        "$hostname"
        ""
        "$directory"
        "\${custom.giturl}"
        "[  ](surface0)"
        "$git_branch"
        "\${custom.git_worktree}"
        "[ㆍ](bg:surface0)"
        "$git_status"
        "[ㆍ](bg:surface0)"
        "$git_metrics"
        "[](surface0)"

        "$line_break"
        "$os"
        # "$shell"
        "$character"
      ];

      right_format = lib.concatStrings [
        "[](fg:surface0)"
        "[ ](bg:surface0)"
        "$gcloud"
        "[ㆍ](bg:surface0)"
        "$aws"
        "[ㆍ](bg:surface0)"
        "$azure"
        "$mise"
        "[ㆍ](bg:surface0)"
        "$cmd_duration"
        # "$all"
      ];

      directory = {
        style = "sapphire";
        format = "[ $path ]($style)";
        truncation_length = 4;
        substitutions = {
          "Documents" = "󰈙 ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
          "Work" = "󰲋 ";
          "Others" = " ";
        };
        use_os_path_sep = true;
      };

      # directory = {
      #   truncate_to_repo = false;
      #   truncation_length = 3;
      #   truncation_symbol = "…/";
      #   read_only_style = "red";
      #   read_only = "";
      #   style = "lavender";
      #   format = "[$path]($style)[$read_only]($read_only_style) ";
      #   before_repo_root_style = "lavender";
      #   repo_root_style = "mauve";
      #   repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style)";
      #   use_os_path_sep = true;
      # };

      username = {
        disabled = true;
        show_always = true;
        style_user = "bg:surface0 fg:text";
        style_root = "bg:surface0 fg:text";
        format = " $user ";
      };

      line_break = {
        disabled = false;
      };

      character = {
        disabled = false;
        success_symbol = "[❯](bold fg:green)";
        error_symbol = "[❯](bold fg:red)";
        vimcmd_symbol = "[❮](bold fg:yellow)";
      };

      hostname = {
        disabled = false;
        ssh_only = true;
        style = "sky";
        format = "[$hostname]($style) ";
        # trim_at = ".com"
      };

      custom.giturl = {
        description = "Display symbol for remote Git server";
        command = ''
          GIT_REMOTE=$(command git ls-remote --get-url 2> /dev/null)
          if [[ "''$GIT_REMOTE" =~ "github" ]]; then
              GIT_REMOTE_SYMBOL=" "
          elif [[ "''$GIT_REMOTE" =~ "gitlab" ]]; then
              GIT_REMOTE_SYMBOL=" "
          elif [[ "''$GIT_REMOTE" =~ "bitbucket" ]]; then
              GIT_REMOTE_SYMBOL=" "
          elif [[ "''$GIT_REMOTE" =~ "git" ]]; then
              GIT_REMOTE_SYMBOL=" "
          else
              GIT_REMOTE_SYMBOL="󰊢 "
          fi
          echo "''$GIT_REMOTE_SYMBOL "
        '';
        when = "git rev-parse --is-inside-work-tree 2> /dev/null";
        format = "$output";
        require_repo = true;
        ignore_timeout = true;
      };

      git_branch = {
        symbol = " ";
        style = "fg:mauve bg:surface0";
        format = "[$symbol$branch]($style)";
      };

      # git_branch = {
      #   symbol = " ";
      #   # symbol = "󰊢 ";
      #   truncation_symbol = "…";
      #   style = "mauve";
      #   always_show_remote = false;
      #   format = " [$symbol$branch(:$remote_branch)]($style)";
      # };

      git_status = {
        format = "[$all_status$ahead_behind]($style)";
        style = "fg:yellow bg:surface0";
        # options available for format
        staged = "[+ \${count}](fg:green bg:surface0)";
        modified = "[ \${count}](fg:yellow bg:surface0)";
        renamed = "[ \${count}](fg:blue bg:surface0)";
        deleted = "[󰆳 \${count}](fg:red bg:surface0)";
        untracked = "[ \${count}](fg:sapphire bg:surface0)";
        stashed = "[≡ \${count}](fg:lavender bg:surface0)";
        conflicted = "[ \${count}](bold fg:red bg:surface0)";

        ahead = "[⇡\${count}](fg:teal bg:surface0)";
        behind = "[⇣\${count}](fg:peach bg:surface0)";
        diverged = "[⇕⇡\${ahead_count}⇣\${behind_count}](fg:mauve bg:surface0)";

        ignore_submodules = false;
      };

      # git_status = {
      #   format = " [$all_status$ahead_behind]($style) ";
      #   style = "red";
      #   conflicted = " ";
      #   # up_to_date = " ";
      #   untracked = " ";
      #   ahead = "⇡\${count}";
      #   behind = "⇣\${count}";
      #   diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
      #   stashed = "󱧕 ";
      #   modified = " ";
      #   staged = "[+\($count\)](green)";
      #   renamed = " ";
      #   deleted = "󰆳 ";
      #   ignore_submodules = true;
      # };

      git_metrics = {
        disabled = false;
        added_style = "fg:green bg:surface0";
        deleted_style = "fg:red bg:surface0";
        format = "[+$added]($added_style)[/](fg:text bg:surface0)[-$deleted]($deleted_style)";
      };

      custom.git_worktree = {
        description = "Show indicator when inside a git worktree";
        command = ''
          if git rev-parse --git-dir >/dev/null 2>&1; then
              common_dir=''$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
              git_dir=''$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)
              if [ "''$common_dir" != "''$git_dir" ]; then
                  echo "⛓ "
              fi
          fi
        '';
        when = "git rev-parse --is-inside-work-tree >/dev/null 2>&1";
        format = "[ㆍ](bg:surface0)[󱘎 \$output]($style)";
        style = "bold fg:green bg:surface0";
        require_repo = true;
        ignore_timeout = true;
      };

      cmd_duration = {
        min_time = 10;
        style = "fg:flamingo bg:surface0";
        format = "[󰔟 $duration]($style)";
      };

      docker_context = {
        disabled = false;
        symbol = " ";
        style = "bg:surface0";
        format = "[$symbol$context]($style)";
      };

      shell = {
        disabled = false;
        fish_indicator = "󰈺";
        powershell_indicator = "";
        cmd_indicator = "";
        zsh_indicator = "󰰸";
        bash_indicator = "";
        unknown_indicator = "?";
        style = "teal";
      };

      gcloud = {
        disabled = false;
        symbol = "󱇶 ";
        style = "bg:surface0";
        format = "[\$symbol(\$project)](\$style)";
        project_aliases = {
          "nics-data-confluence" = "DCF";
        };
      };

      aws = {
        disabled = false;
        symbol = "󰸏 ";
        # format = "[\$symbol(\$profile)(\\(\$region\\) )](\$style)";
        style = "bg:surface0";
        format = "[\$symbol(\$profile)](\$style)";
        profile_aliases = {
          "default" = "nics";
        };
      };

      azure = {
        disabled = false;
        symbol = "󰠅 ";
        style = "bg:surface0";
        format = "[\$symbol(\$subscription)](\$style)";
        subscription_aliases = {
          "Azure_nics2" = "nics";
        };
      };

      mise = {
        disabled = false;
        symbol = " 󰭼 ";
        style = "fg:pink bg:surface0";
        healthy_symbol = " ";
        unhealthy_symbol = " ";
        format = "[ㆍ](bg:surface0)[\$symbol\$health](\$style)";
      };

      python = {
        disabled = false;
        style = "yellow bold";
        format = "[\${symbol}\${pyenv_prefix}(\${version})(\($virtualenv\))]($style)";
        version_format = "v\${raw}";
        symbol = "󰌠 ";
      };

      conda = {
        disabled = false;
        style = "dimmed green";
        format = "[$symbol$environment]($style) ";
        symbol = " ";
        truncation_length = 1;
        ignore_base = false;
      };

      # Shows an icon that should be included by zshrc script based on the distribution or os
      os = {
        disabled = false;
        style = "teal";
        format = "[$symbol ]($style)";
        symbols = {
          AlmaLinux = "";
          Alpaquita = "";
          Alpine = "";
          Amazon = "";
          Android = "";
          Arch = "";
          Artix = "";
          CentOS = "";
          Debian = "";
          DragonFly = "";
          Emscripten = "";
          EndeavourOS = "";
          Fedora = "";
          FreeBSD = "";
          Garuda = "󰛓";
          Gentoo = "";
          HardenedBSD = "󰞌";
          Illumos = "";
          Kali = "";
          Linux = "";
          Mabox = "";
          Macos = "";
          Manjaro = "";
          Mariner = "";
          MidnightBSD = "";
          Mint = "󰣭";
          NetBSD = "";
          NixOS = "";
          OpenBSD = "";
          openSUSE = "";
          OracleLinux = "󰌷";
          Pop = "";
          Raspbian = "";
          RedHatEnterprise = "󱄛";
          Redhat = "󱄛";
          Redox = "󰀘";
          RockyLinux = "";
          SUSE = "";
          Solus = "";
          Ubuntu = "";
          Unknown = "";
          Void = "";
          Windows = "";
        };
      };
    };
  };
}
