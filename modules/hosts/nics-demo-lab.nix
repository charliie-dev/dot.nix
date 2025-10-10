{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  ds-hm-wrapper = base-attr.determinate-hm-wrapper;
  inherit (base-attr)
    nixpkgs
    catppuccin
    hm_ver
    nur
    nix-index-database
    src
    ;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        nur.overlays.default
        ds-hm-wrapper.overlays.default
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit src;
      roles = [
        "dev-core"
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
