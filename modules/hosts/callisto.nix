{ nixgl-attr, ... }:
let
  hm = nixgl-attr.home-manager;
  ds-hm-wrapper = nixgl-attr.determinate-hm-wrapper;
  inherit (nixgl-attr)
    nixpkgs
    catppuccin
    hm_ver
    nur
    nix-index-database
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
      catppuccin.homeModules.catppuccin
      nix-index-database.homeModules.nix-index
      {
        home = {
          username = "charles";
          homeDirectory = "/home/charles";
          stateVersion = hm_ver;
          shell.enableZshIntegration = true;
          sessionPath = [ "/nix/var/nix/profiles/default/bin" ];
        };
      }
    ];
  };
}
