{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  inherit (base-attr)
    nixpkgs
    nur
    nix-index-database
    agenix
    catppuccin
    src
    hm_ver
    ;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        nur.overlays.default
        agenix.overlays.default
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
          inherit (import "${src}/modules/targets/genericLinux-gpu.nix") genericLinux;
        };
        news.display = "silent";
      }
    ];
  };
}
