{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # https://github.com/nix-community/neovim-nightly-overlay/
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = { self, nixpkgs, home-manager, neovim-nightly-overlay, ... }:
    let
      # $nix eval --impure --raw --expr 'builtins.currentSystem'
      arch = builtins.currentSystem;
      lib = home-manager.lib;
      overlays = [
        neovim-nightly-overlay.overlay
      ];
    in
    {
      defaultPackage = {
        "x86_64-linux" = home-manager.defaultPackage."x86_64-linux";
        "aarch64-linux" = home-manager.defaultPackage."aarch64-linux";
        "aarch64-darwin" = home-manager.defaultPackage."aarch64-darwin";
      };


      homeConfigurations = {
        charles = lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit arch; overlays = overlays; };
          modules = [ ./home.nix ];
        };
      };
    };
}
