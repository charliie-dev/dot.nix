{ nixgl-attr, ... }:
let
  hm = nixgl-attr.home-manager;
  ds-hm-wrapper = nixgl-attr.determinate-hm-wrapper;
  inherit (nixgl-attr)
    nixpkgs
    nur
    nix-index-database
    agenix
    catppuccin
    src
    hm_ver
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
        ds-hm-wrapper.overlays.default
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit src nixgl;
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
      {
        home = {
          username = "charles";
          homeDirectory = "/home/charles";
          stateVersion = hm_ver;
        };
        target = {
          inherit (import "${src}/modules/target/genericLinux-gpu.nix") genericLinux;
        };
      }
    ];
  };
}
