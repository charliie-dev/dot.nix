# hosts.nix — All host definitions in one place
# enableSecrets: per-host flag, set to false for first-time deploys on new machines
{
  "charles@m3pro" = {
    system = "aarch64-darwin";
    hostFile = ./modules/hosts/m3pro.nix;
    enableSecrets = true;
  };
  "charles@callisto" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/callisto.nix;
    enableSecrets = true;
  };
  "charles@pluto" = {
    system = "aarch64-linux";
    hostFile = ./modules/hosts/pluto.nix;
    enableSecrets = true;
  };
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@nics-demo-lab" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@nate-test" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@tmp-gpu" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps-gpu.nix;
    gpu = true;
    enableSecrets = true;
  };
  "charles@pg-proxy-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-primary-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-replica1-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  "charles@pg-replica2-dev" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = true;
  };
  # Example new host:
  # "charles@new-server" = {
  #   system = "x86_64-linux";
  #   hostFile = ./modules/hosts/x86-vps.nix;
  #   enableSecrets = false;  # flip to true after first deploy
  # };
  "charles@testvm" = {
    system = "x86_64-linux";
    hostFile = ./modules/hosts/x86-vps.nix;
    enableSecrets = false;
  };
}
