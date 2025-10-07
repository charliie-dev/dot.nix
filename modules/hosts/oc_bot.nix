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
  hsot = hm.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
    extraSpecialArgs = {
      # inherit inputs;
      roles = [
        "dev-core"
      ];
    };
    modules = [
      # determinate.nixosModules.default
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
