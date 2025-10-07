{
  base-attr,
  ...
}:
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
      system = "aarch64-darwin";
      overlays = [
        nur.overlays.default
      ];
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      # inherit inputs;
      roles = [
        "dev-core"
        "dev-extra"
        "top"
        "darwin-top"
      ];
    };
    modules = [
      ../core.nix
      catppuccin.homeModules.catppuccin
      {
        home = {
          username = "charles";
          homeDirectory = "/Users/charles";
          stateVersion = hm_ver;
          shell.enableZshIntegration = true;
        };
      }
    ];
  };
}
