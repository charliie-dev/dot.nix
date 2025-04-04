{
  description = "Home Manager configuration";
  inputs = {
    # nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # neovim.url = "github:nix-community/neovim-nightly-overlay";
    catppuccin.url = "github:catppuccin/nix/main";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    catppuccin,
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    # overlays = [
    #   inputs.neovim.overlay
    # ];
    # This is a function that generates an attribute by calling a function you
    # pass to it, with each system as an argument
    forAllSystems = nixpkgs.lib.genAttrs systems;
    hm = home-manager;
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
    # Formatter for your nix files, available through 'nix fmt'
    # Other options beside 'alejandra' include 'nixpkgs-fmt'
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Your custom packages and modifications, exported as overlays
    overlays = import ./overlays {inherit inputs;};
    # Reusable home-manager modules you might want to export
    # These are usually stuff you would upstream into home-manager
    # homeManagerModules = import ./modules/home-manager;
    defaultPackage = {
      "x86_64-linux" = hm.defaultPackage."x86_64-linux";
      "aarch64-linux" = hm.defaultPackage."aarch64-linux";
      "aarch64-darwin" = hm.defaultPackage."aarch64-darwin";
    };

    homeConfigurations = {
      "charles@m3pro.local" = hm.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./home-darwin.nix
          catppuccin.homeModules.catppuccin
        ];
      };
      "charles@bot" = hm.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./home.nix
          catppuccin.homeModules.catppuccin
        ];
      };
      "charles@gemini" = hm.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./home.nix
          catppuccin.homeModules.catppuccin
        ];
      };
      "charles@RDSrv01" = hm.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./home.nix
          catppuccin.homeModules.catppuccin
        ];
      };
      "charles@callisto" = hm.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs outputs;
        };
        modules = [
          ./home.nix
          catppuccin.homeModules.catppuccin
        ];
      };
    };
  };
}
