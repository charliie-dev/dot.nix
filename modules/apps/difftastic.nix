{
  # Syntax-aware diff
  difftastic = {
    enable = false;
    git = {
      enable = true;
      diffToolMode = false;
    };
    options = {
      color = "always";
      background = "dark";
      display = "side-by-side"; # "side-by-side", "side-by-side-show-both", "inline"
    };
  };
}
