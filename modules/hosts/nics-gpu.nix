{ gpu-attr, ... }:
let
  hm = gpu-attr.home-manager;
  inherit (gpu-attr)
    agenix
    catppuccin
    hm_ver
    nix-index-database
    nixpkgs
    nur
    src
    nixgl
    ;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        nur.overlays.default
        agenix.overlays.default
        nixgl.overlay
      ];
      config = {
        allowUnfree = true;
        nvidia.acceptLicense = true;
      };
    };
    extraSpecialArgs = {
      inherit src;
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
      nix-index-database.homeModules.nix-index
      agenix.homeManagerModules.default
      catppuccin.homeModules.catppuccin
      nur.modules.homeManager.default
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
