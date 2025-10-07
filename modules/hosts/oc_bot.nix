{ base-attr, ... }:
let
  hm = base-attr.home-manager;
  inherit (base-attr) nixpkgs;
  inherit (base-attr) catppuccin;
  inherit (base-attr) hm_ver;
  inherit (base-attr) nur;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      overlays = [
        nur.overlays.default
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      # inherit inputs;
      roles = [
        "dev-core"
      ];
    };
    modules = [
      ../core.nix
      catppuccin.homeModules.catppuccin
      {
        home = {
          username = "charles";
          homeDirectory = "/home/charles";
          stateVersion = hm_ver;
          shell.enableZshIntegration = true;
        };
      }
    ];
  };
}
