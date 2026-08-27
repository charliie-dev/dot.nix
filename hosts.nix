# hosts.nix — All host definitions in one place
# enableSecrets: application secrets (Doppler token and process-scoped wrappers)
# enableSshSecrets: SOPS SSH baseline; defaults to enableSecrets when unspecified
# sharedConfig: point to another host name to reuse its homeManagerConfiguration
# nvidiaGpu: enable the nixGL/NVIDIA variant of the generic Linux platform
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
    ];
    homeDirectory = "/home/charles";
    nvidiaGpu = true;
    enableSecrets = true;
    silent = true;
  };

  # Canonical VPS config (built once)
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    enableSecrets = false;
    enableSshSecrets = true;
    silent = true;
  };
  # Shared aliases — application secrets stay off while the SSH baseline is inherited.
  "charles@rdsrv02" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
  "charles@ra-lab" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
  "charles@nate-test" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
  };
  "charles@testvm" = {
    sharedConfig = "charles@RDSrv01";
    system = "x86_64-linux";
    enableSecrets = false;
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
