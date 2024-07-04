{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # neovim.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = { self, ... }@inputs:
    let
      hm = inputs.home-manager;
      # $nix eval --impure --raw --expr 'builtins.currentSystem'
      system = builtins.currentSystem;
      # overlays = [
      #   inputs.neovim.overlay
      # ];
    in
    {
      homeConfigurations = {
        charles = hm.lib.homeManagerConfiguration {
          pkgs = (import inputs.nixpkgs) {
            inherit system;
            config.allowUnfree = true;
            # overlays = overlays;
          };
          modules = [ ./home.nix ];
        };
      };
    };
}
