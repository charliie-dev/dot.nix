{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  inherit (base-attr)
    agenix
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
      system = "aarch64-linux";
      overlays = [
        # nur.overlays.default
        agenix.overlays.default
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
      agenix.homeManagerModules.default
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
        news.display = "silent";
      }
    ];
  };
}
