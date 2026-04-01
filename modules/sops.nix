{ config, src, ... }:
{
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
}
