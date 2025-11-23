{ pkgs, ... }:
{
  yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "yz";
    extraPackages = with pkgs; [
      file # for file type detection
      # ffmpeg # for video thumbnails
      # _7zz-rar # for archive extraction and preview, requires non-standalone version
      ouch # # ouch stands for Obvious Unified Compression Helper
      poppler # for PDF preview
      resvg # for SVG preview
      perl540Packages.ImageMagick # for Font, HEIC, and JPEG XL preview, >= 7.1.1
      nur.repos.charmbracelet.glow # Render markdown on the CLI, with pizzazz
      yq-go # jq but for YAML, JSON, XML, CSV, TOML
      duckdb
    ];

    settings = {
      mgr = {
        ratio = [
          2
          4
          3
        ];
        show_hidden = true;
        sort_by = "natural";
        sort_dir_first = true;
        prepend_keymap = [
          {
            on = [
              "R"
              "D"
            ];
            run = "plugin sudo -- remove --permanently";
            desc = "sudo delete";
          }
        ];
      };
      plugin = {
        prepend_fetchers = [
          {
            id = "mime";
            name = "*";
            run = "mime-ext";
            prio = "high";
          }
          {
            id = "git";
            name = "*";
            run = "git";
          }
          {
            id = "git";
            name = "*/";
            run = "git";
          }
        ];
        prepend_previewers = [
          {
            mime = "application/*zip";
            run = "ouch";
          }
          {
            mime = "application/x-{tar,bzip*,7z-compressed,xz,rar,zstd}";
            run = "ouch";
          }
          {
            mime = "application/{vnd.rar,xz,zstd,java-archive}";
            run = "ouch";
          }
          {
            name = "*.md";
            run = ''
              piper -- CLICOLOR_FORCE=1 glow -w=$w -s=dark "$1"
            '';
          }
          {
            mime = "inode/directory";
            run = ''
              piper -- lsd -A --color always --tree "$1"
            '';
          }
          {
            mime = "application/json";
            run = ''
              piper -- yq -CP -oj "$1"
            '';
          }
          {
            name = "*.parquet";
            run = "duckdb";
          }
          {
            name = "*.xlsx";
            run = "duckdb";
          }
          {
            name = "*.db";
            run = "duckdb";
          }
          {
            name = "*.duckdb";
            run = "duckdb";
          }
        ];
      };
    };

    plugins = with pkgs.yaziPlugins; {
      inherit
        chmod
        full-border
        toggle-pane
        smart-enter
        git
        piper
        starship
        duckdb
        ouch
        sudo
        ;
    };

    initLua = ''
      require("full-border"):setup()
      require("git"):setup()
      require("starship"):setup()
      require("duckdb"):setup()
    '';

    keymap = {
      mgr.prepend_keymap = [
        {
          on = "T";
          run = "plugin toggle-pane max-preview";
          desc = "Maximize or restore the preview pane";
        }
        {
          on = [
            "c"
            "m"
          ];
          run = "plugin chmod";
          desc = "Chmod on selected files";
        }
        {
          on = "H";
          run = "plugin duckdb -1";
          desc = "Scroll one column to the left";
        }
        {
          on = "L";
          run = "plugin duckdb +1";
          desc = "Scroll one column to the right";
        }
        {
          on = [
            "g"
            "o"
          ];
          run = "plugin duckdb -open";
          desc = "open with duckdb";
        }
        {
          on = [
            "g"
            "u"
          ];
          run = "plugin duckdb -ui";
          desc = "open with duckdb ui";
        }
      ];
    };
  };
}
