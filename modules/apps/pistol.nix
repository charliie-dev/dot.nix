{
  pistol = {
    enable = true;
    associations = [
      {
        fpath = ".*.md$";
        command = "glow -s dark %pistol-filename%";
      }
      {
        fpath = ".*.log$";
        command = "lnav -n %pistol-filename%";
      }
      {
        mime = "inode/directory";
        command = "lsd -A --color always --tree %pistol-filename%";
      }
      {
        mime = "text/.*";
        command = "bat %pistol-filename% --style auto";
      }
      {
        mime = "image/.*";
        command = "chafa --passthrough=auto --polite=on --exact-size=off --clear --align=top,left %pistol-filename%";
      }
      {
        mime = "application/*";
        command = "hexyl %pistol-filename%";
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
        mime = "application/json";
        command = "yq -CP -oj %pistol-filename%";
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
        mime = "application/json";
        command = "yq -CP -oj %pistol-filename%";
      }

    ];
  };
}
