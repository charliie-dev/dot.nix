{ config, lib, ... }:
{
  starship = {
    enable = true;
    configPath = "${config.xdg.configHome}/starship/starship.toml";
    enableZshIntegration = false; # self-definded smartcache in conf.d/zsh
    enableIonIntegration = false;
    settings = {

      # Inserts a blank line between shell prompts
      add_newline = true;

      # Change command timeout from 500 to 1000 ms
      command_timeout = 10000;

      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_metrics"
        "$git_status"
        "$package"
        "$docker_context"
        "$cmd_duration"
        "$line_break"
        "$os"
        "$shell"
        "$character"
      ];

      username = {
        disabled = false;
        show_always = true;
        style_user = "green";
        style_root = "red";
        format = "[$user ]($style)";
      };

      hostname = {
        disabled = false;
        ssh_only = true;
        ssh_symbol = " ";
        style = "sky";
        format = "@[$hostname]($style) ";
        # trim_at = ".com"
      };

      directory = {
        truncate_to_repo = false;
        truncation_length = 3;
        truncation_symbol = "…/";
        read_only_style = "red";
        read_only = "";
        style = "lavender";
        format = "[$path]($style)[$read_only]($read_only_style) ";
        before_repo_root_style = "lavender";
        repo_root_style = "mauve";
        repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style)";
        use_os_path_sep = true;
      };

      cmd_duration = {
        min_time = 10;
        style = "yellow";
        format = "[󰔟 $duration]($style)";
      };

      git_branch = {
        symbol = " ";
        # symbol = "󰊢 ";
        truncation_symbol = "…";
        style = "mauve";
        always_show_remote = false;
        format = " [$symbol$branch(:$remote_branch)]($style)";
      };

      git_status = {
        format = " [$all_status$ahead_behind]($style) ";
        style = "red";
        conflicted = " ";
        # up_to_date = " ";
        untracked = " ";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        stashed = "󱧕 ";
        modified = " ";
        staged = "[+\($count\)](green)";
        renamed = " ";
        deleted = "󰆳 ";
        ignore_submodules = true;
      };

      git_metrics = {
        disabled = false;
        added_style = "green";
        deleted_style = "red";
        format = " [+$added]($added_style)/[-$deleted]($deleted_style)";
      };

      git_commit = {
        tag_symbol = "  ";
      };

      package = {
        disabled = true;
        style = "text";
        symbol = "󰏗 ";
        format = "[$symbol$version]($style)";
      };

      docker_context = {
        disabled = false;
        symbol = " ";
        format = "[$symbol$context]($style)";
      };
      container = {
        disabled = false;
        format = "[$symbol \[$name\]]($style) ";
      };

      character = {
        success_symbol = "[❯](green)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };

      # Shows an icon that should be included by zshrc script based on the distribution or os
      os = {
        disabled = false;
        style = "teal";
        format = "[$symbol ]($style)";
      };

      os.symbols = {
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

      #### Disabled modules ####
      localip = {
        disabled = true;
      };

      memory_usage = {
        disabled = true;
      };

      time = {
        disabled = true;
      };

      jobs = {
        disabled = true;
      };

      battery = {
        disabled = true;
      };

      azure = {
        disabled = false;
        symbol = "󰠅 ";
      };

      aws = {
        disabled = false;
        symbol = " ";
      };

      gcloud = {
        disabled = false;
        symbol = " ";
      };

      hg_branch = {
        disabled = false;
        symbol = " ";
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

      lua = {
        disabled = false;
        symbol = " ";
      };

      nix_shell = {
        disabled = false;
        symbol = "󱄅 ";
      };

      haskell = {
        disabled = false;
        symbol = " ";
      };

      c = {
        disabled = false;
        symbol = " ";
      };

      nodejs = {
        disabled = false;
        symbol = " ";
      };

      rust = {
        disabled = false;
        symbol = " ";
      };

      golang = {
        disabled = false;
        symbol = " ";
      };

      swift = {
        disabled = false;
        symbol = " ";
      };

      zig = {
        disabled = false;
        symbol = " ";
      };

      mise = {
        disabled = false;
        symbol = "mise ";
      };
    };
  };
}
