{
  config,
  lib,
  enableSshSecrets ? false,
  ...
}:
{
  home = {
    activation.sshControlDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.xdg.cacheHome}/ssh"
      chmod 700 "${config.xdg.cacheHome}/ssh"
    '';

    # This include is evaluated before the encrypted host configuration. OpenSSH
    # uses the first value it obtains, so it overrides the legacy per-host
    # ~/.ssh/sockets ControlPath without duplicating every secret host block.
    file.".ssh/config.d/home-manager.conf".text = ''
      Host *
        ControlPath ~/.cache/ssh/%C
    '';
  };

  programs.ssh = {
    enable = true;
    includes = [
      "~/.ssh/override_config"
      "~/.ssh/config.d/home-manager.conf"
    ]
    ++ lib.optionals enableSshSecrets [
      # `sunlei/zsh-ssh` cannot resolve an absolute deployment path.
      "~/.ssh/host_configuration"
    ];
    settings."*" = {
      AddKeysToAgent = "yes";
      IdentitiesOnly = true;
      Compression = true;
      ForwardAgent = false;
      HashKnownHosts = false;
      # IdentityFile is set by modules/secrets/sops.nix when secrets are enabled.
      ServerAliveInterval = 300;
      ServerAliveCountMax = 10;
    };
    enableDefaultConfig = false; # this option will be deprecated, so set it to false
  };
}
