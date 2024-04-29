{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-utils.url = "github:numtide/flake-utils";
    # flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
    neovim.url = "github:nix-community/neovim-nightly-overlay";

  };

  outputs = { self, ... }@inputs:
    let
      hm = inputs.home-manager;
      # $nix eval --impure --raw --expr 'builtins.currentSystem'
      system = builtins.currentSystem;
      overlays = [
        inputs.neovim.overlay
      ];
    in
    {
      homeConfigurations = {
        charles = hm.lib.homeManagerConfiguration {
          pkgs = (import inputs.nixpkgs) {
            inherit system;
            overlays = overlays;
          };
          modules = [ ./home.nix ];
        };
      };
    };
}
