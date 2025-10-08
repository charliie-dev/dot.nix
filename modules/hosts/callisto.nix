{ nixgl-attr, ... }:
let
  hm = nixgl-attr.home-manager;
  inherit (nixgl-attr) nixpkgs;
  inherit (nixgl-attr) catppuccin;
  inherit (nixgl-attr) hm_ver;
  inherit (nixgl-attr) nur;
  inherit (nixgl-attr) nixgl;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        nur.overlays.default
        nixgl.overlay
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      # inherit inputs;
      inherit nixgl;
      roles = [
        "dev-core"
        "dev-extra"
        "top"
        "linux-top"
        "nvidia-gpu"
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
