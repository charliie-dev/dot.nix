{
  programs.carapace.enable = true;
  programs.carapace.enableZshIntegration = true;
  xdg.configFile."carapace/specs".recursive = true;
  xdg.configFile."carapace/specs".source = ./carapace/specs;
}
