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
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    extraSpecialArgs = {
      # inherit inputs;
      # inherit nixgl;
      roles = [
        "dev-core"
        "dev-extra"
        "top"
        "linux-top"
        "nvidia-gpu"
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
