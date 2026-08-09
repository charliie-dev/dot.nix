# hosts.nix — All host definitions in one place
# enableSecrets: per-host flag, set to false for first-time deploys on new machines
# sharedConfig: point to another host name to reuse its homeManagerConfiguration
# gpu: enable the nixGL/NVIDIA variant of the generic Linux platform
{
  "charles@24041-LABNB01" = {
    system = "aarch64-darwin";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
    ];
    homeDirectory = "/Users/charles";
    enableSecrets = true;
  };
  # home-manager switch uses hostname with .local suffix on macOS
  "charles@24041-LABNB01.local" = {
    sharedConfig = "charles@24041-LABNB01";
    system = "aarch64-darwin";
  };
  "charles@callisto" = {
    system = "x86_64-linux";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
    ];
    homeDirectory = "/home/charles";
    enableSecrets = true;
  };
  "charles@pluto" = {
    system = "aarch64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    enableSecrets = true;
    silent = true;
  };
  "charles@tmp-gpu" = {
    system = "x86_64-linux";
    roles = [
      "dev-core"
      "dev-extra"
      "top"
      "nvidia-gpu"
    ];
    homeDirectory = "/home/charles";
    gpu = true;
    enableSecrets = true;
    silent = true;
  };

  # Canonical VPS config (built once)
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    enableSecrets = true;
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
  "charles@prod-deploy" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
  "charles@ra06-claude" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
}
