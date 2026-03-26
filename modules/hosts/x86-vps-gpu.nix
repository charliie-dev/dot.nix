{ gpu-attr, ... }:
let
  inherit (gpu-attr) nixgl;
  hm = gpu-attr.base-attr.home-manager;
  inherit (gpu-attr.base-attr)
    sops-nix
    catppuccin
    hm_ver
    nix-index-database
    nixpkgs
    # nur
    snitch
    src
    ;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        # nur.overlays.default
        nixgl.overlay
      ];
      config = {
        allowUnfree = true;
        nvidia.acceptLicense = true;
      };
    };
    extraSpecialArgs = {
      inherit src;
      inherit (gpu-attr.base-attr) enableSecrets;
      roles = [
        "dev-core"
        "dev-extra"
        "top"
        "linux-top"
        "nvidia-gpu"
      ];
    };
    modules = [
      "${src}/modules/core.nix"
      sops-nix.homeManagerModules.sops
      catppuccin.homeModules.catppuccin
      nix-index-database.homeModules.nix-index
      # nur.modules.homeManager.default
      snitch.homeManagerModules.default
      {
        home = {
          username = "charles";
          homeDirectory = "/home/charles";
          stateVersion = hm_ver;
        };
        targets = {
          inherit (import "${src}/modules/targets/genericLinux-gpu.nix" { inherit nixgl; }) genericLinux;
        };
        news.display = "silent";
      }
    ];
  };
}
