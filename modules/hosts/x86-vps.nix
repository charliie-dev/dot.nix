{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  inherit (base-attr)
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
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit src;
      inherit (base-attr) enableSecrets;
      roles = [
        "dev-core"
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
          inherit (import "${src}/modules/targets/genericLinux.nix") genericLinux;
        };
        news.display = "silent";
      }
    ];
  };
}
