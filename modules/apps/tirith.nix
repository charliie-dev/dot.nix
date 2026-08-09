{
  tirith = {
    enable = true;
    enableZshIntegration = false; # loaded manually in zsh/keybindings.nix to control ordering
    policy = {
      severity_overrides.schemeless_to_sink = "INFO";
      allowlist_rules = [
        {
          rule_id = "docker_untrusted_registry";
          patterns = [ "dhi.io/" ];
        }
      ];
    };
  };
}
