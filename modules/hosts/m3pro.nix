{
  shorthand,
  ...
}:
let
  hm = shorthand.home-manager;
  inherit (shorthand) nixpkgs;
  inherit (shorthand) catppuccin;
  inherit (shorthand) hm_ver;
in
{
  host = hm.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.aarch64-darwin;
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
      # determinate.nixosModules.default
      ../core.nix
      # ./home-darwin.nix
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
