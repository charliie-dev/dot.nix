_: {
  ssh = {
    enable = true;
    includes = [
      "~/.ssh/override_config"
      # "${config.age.secrets.ssh_host_config.path}" # `sunlei/zsh-ssh` can't resolve absolute path
      "~/.ssh/host_configuration"
    ];
    settings."*" = {
      AddKeysToAgent = "yes";
      IdentitiesOnly = true;
      Compression = true;
      ForwardAgent = false;
      HashKnownHosts = false;
      # IdentityFile set by core.nix mkIf enableSecrets
      ServerAliveInterval = 300;
      ServerAliveCountMax = 10;
    };
    enableDefaultConfig = false; # this option will be deprecated, so set it to false
  };
}
