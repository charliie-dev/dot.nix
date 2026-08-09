{
  config,
  lib,
  src,
  enableSecrets ? false,
  ...
}:
lib.mkIf enableSecrets {
  sops = {
    defaultSopsFile = "${src}/conf.d/sops/secrets.yaml";
    age.keyFile = "${config.xdg.configHome}/age/keys.txt";

    secrets = {
      ssh_ed25519 = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "0600";
      };
      ssh_ed25519_pub = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
        mode = "0644";
      };
      host_configuration = {
        path = "${config.home.homeDirectory}/.ssh/host_configuration";
      };
      allowed_signers = {
        path = "${config.xdg.configHome}/git/allowed_signers";
      };
      doppler_token = {
        path = "${config.xdg.dataHome}/doppler/token";
        mode = "0400";
      };
    };
  };

  home.activation.ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -f "${config.home.homeDirectory}/.ssh/id_ed25519.pub" ]; then
      if [ ! -f "${config.home.homeDirectory}/.ssh/authorized_keys" ]; then
        touch "${config.home.homeDirectory}/.ssh/authorized_keys"
      fi
      # Compare key type + body (cols 1-2), ignoring the comment field.
      read -r ktype kbody _ < "${config.home.homeDirectory}/.ssh/id_ed25519.pub"
      if ! grep -qF "$ktype $kbody" "${config.home.homeDirectory}/.ssh/authorized_keys"; then
        cat "${config.home.homeDirectory}/.ssh/id_ed25519.pub" \
          >> "${config.home.homeDirectory}/.ssh/authorized_keys"
      fi
    fi
  '';

  programs = {
    git = {
      signing.key = config.sops.secrets.ssh_ed25519_pub.path;
      settings.gpg.ssh.allowedSignersFile = config.sops.secrets.allowed_signers.path;
    };
    ssh.settings."*".IdentityFile = config.sops.secrets.ssh_ed25519.path;
  };
}
