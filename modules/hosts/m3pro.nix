{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  ds-hm-wrapper = base-attr.determinate-hm-wrapper;
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
      system = "aarch64-darwin";
      overlays = [
        nur.overlays.default
        agenix.overlays.default
        ds-hm-wrapper.overlays.default
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit src;
      roles = [
        "dev-core"
        "dev-extra"
        "top"
        "darwin-top"
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
          homeDirectory = "/Users/charles";
          stateVersion = hm_ver;
        };
        target = {
          inherit (import "${src}/modules/targets/darwin.nix") darwin;
        };
      }
    ];
  };
}
