{
  pistol = {
    enable = true;
    associations = [
      {
        fpath = ".*.md$";
        command = "bat --color=always --style=plain --language=markdown %pistol-filename%";
      }
      {
        fpath = ".*.log$";
        command = "lnav -n %pistol-filename%";
      }
      {
        mime = "inode/directory";
        command = "lsd -A --color=always --blocks git,name %pistol-filename%";
      }
      {
        mime = "text/.*";
        command = "bat %pistol-filename% --style auto";
      }
      {
        mime = "image/.*";
        command = "sh: chafa --format=symbols --polite=on --align=top,left --size=\${FZF_PREVIEW_COLUMNS:-80}x\${FZF_PREVIEW_LINES:-24} %pistol-filename%";
      }
      {
        mime = "application/gzip";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/zip";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/x-tar";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/x-bzip2";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/x-xz";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/zstd";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/x-7z-compressed";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/x-rar";
        command = "ouch list %pistol-filename% --tree";
      }
      {
        mime = "application/pdf";
        command = "sh: pdftotext %pistol-filename% -";
      }
      {
        mime = "application/json";
        command = "yq -CP -oj %pistol-filename%";
      }
      {
        mime = "application/yaml";
        command = "yq -CP %pistol-filename%";
      }
      {
        mime = "application/toml";
        command = "yq -CP -oy %pistol-filename%";
      }
      {
        mime = "application/xml";
        command = "yq -CP -ox %pistol-filename%";
      }
      {
        mime = "application/csv";
        command = "yq -CP -oc %pistol-filename%";
      }
      {
        mime = "application/tsv";
        command = "yq -CP -ot %pistol-filename%";
      }
      {
        mime = "application/*";
        command = "hexyl %pistol-filename%";
      }
    ];
  };
}
