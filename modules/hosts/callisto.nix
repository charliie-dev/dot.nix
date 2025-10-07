{
  gpu-attr,
  ...
}:
let
  hm = gpu-attr.home-manager;
  inherit (gpu-attr) nixpkgs;
  inherit (gpu-attr) catppuccin;
  inherit (gpu-attr) hm_ver;
  inherit (gpu-attr) nur;
  inherit (gpu-attr) nixgl;
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
