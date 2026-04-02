# hosts.nix — All host definitions in one place
# enableSecrets: per-host flag, set to false for first-time deploys on new machines
# sharedConfig: point to another host name to reuse its homeManagerConfiguration
{
  "charles@m3pro" = {
    system = "aarch64-darwin";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
      "darwin-top"
    ];
    homeDirectory = "/Users/charles";
    target = "darwin";
  };
  "charles@callisto" = {
    system = "x86_64-linux";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
      "linux-top"
    ];
    homeDirectory = "/home/charles";
    target = "genericLinux";
  };
  "charles@pluto" = {
    system = "aarch64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    silent = true;
  };
  "charles@tmp-gpu" = {
    system = "x86_64-linux";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
      "linux-top"
      "nvidia-gpu"
    ];
    homeDirectory = "/home/charles";
    target = "genericLinux-gpu";
    gpu = true;
    silent = true;
  };

  # Canonical VPS config (built once)
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    target = "genericLinux";
    silent = true;
  };
  # Shared aliases — reuse RDSrv01's eval result
  "charles@ra-lab" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
  };
  "charles@nate-test" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
  };
  "charles@testvm" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
  };
  "charles@dcf-dev" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
}
