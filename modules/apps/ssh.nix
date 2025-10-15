{ config, ... }:
{
  ssh = {
    enable = true;
    includes = [
      "~/.ssh/override_config"
      # "${config.age.secrets.ssh_host_config.path}" # `sunlei/zsh-ssh` can't resolve absolute path
      "~/.ssh/host_configuration"
    ];
    matchBlocks."*" = {
      addKeysToAgent = "no";
      compression = true;
      forwardAgent = false;
      hashKnownHosts = false;
      identityFile = "${config.age.secrets.ssh_ed25519.path}";
      serverAliveInterval = 300;
      serverAliveCountMax = 10;
    };
    enableDefaultConfig = false; # this option will be deprecated, so set it to false
  };
}
