{
  # Syntax-aware diff
  difftastic = {
    enable = false;
    git = {
      enable = true;
      mode = "external"; # "external" | "difftool" | "both"
    };
    options = {
      color = "always";
      background = "dark";
      display = "side-by-side"; # "side-by-side", "side-by-side-show-both", "inline"
    };
  };
}
