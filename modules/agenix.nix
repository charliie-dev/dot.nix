{ config, src, ... }:
{
  age = {
    identityPaths = [ "${config.xdg.configHome}/age/keys.txt" ];
    secrets = {
      ssh_ed25519 = {
        file = "${src}/conf.d/ages/ssh_ed25519.age";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "600";
      };
      ssh_ed25519_pub = {
        file = "${src}/conf.d/ages/ssh_ed25519_pub.age";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
        mode = "644";
      };
      ssh_host_config = {
        file = "${src}/conf.d/ages/host_configuration.age";
        path = "${config.home.homeDirectory}/.ssh/host_configuration";
      };
    };
  };
}
