{
  description = "Home Manager configuration";
  inputs = {
    # determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # neovim.url = "github:nix-community/neovim-nightly-overlay";
    catppuccin.url = "github:catppuccin/nix/main";
    # nixgl.url = "github:nix-community/nixGL/main";
    nix-formatter-pack.url = "github:Gerschtli/nix-formatter-pack";
  };

  outputs =
    {
      # determinate,
      nixpkgs,
      home-manager,
      catppuccin,
      # nixgl,
      nix-formatter-pack,
      ...
    }:
    let
      # Supported systems for your flake packages, shell, etc.
      systems = nixpkgs.lib.systems.flakeExposed;
      forEachSystem = nixpkgs.lib.genAttrs systems;

      formatterPackArgsPerSystem = forEachSystem (system: {
        inherit nixpkgs system;
        checkFiles = [ ./. ];
        config = {
          tools = {
            alejandra.enable = false;
            deadnix.enable = false;
            nixfmt.enable = true;
            statix.enable = true;
          };
        };
      });

      # Alias
      nixfmtpack = nix-formatter-pack;
      shorthand = {
        inherit home-manager;
        hm_ver = "25.11";
        inherit nixpkgs;
        inherit catppuccin;
      };
    in
    {
      checks = forEachSystem (system: {
        nix-formatter-pack-check = nixfmtpack.lib.mkCheck formatterPackArgsPerSystem.${system};
      });

      formatter = forEachSystem (system: nixfmtpack.lib.mkFormatter formatterPackArgsPerSystem.${system});

      # Define `homeModules`, `homeConfigurations`,
      # `nixosConfigurations`, etc here
      homeConfigurations = {
        "charles@m3pro.local" = (import ./modules/hosts/m3pro.nix { inherit shorthand; }).host;
        "charles@callisto" = (import ./modules/hosts/callisto.nix { inherit shorthand; }).host;
        "charles@RDSrv01" = (import ./modules/hosts/rdsrv01.nix { inherit shorthand; }).host;
        "charles@bot" = (import ./modules/hosts/oc_bot.nix { inherit shorthand; }).host;
        "charles@nics-demo-lab" = (import ./modules/hosts/nics-demo-lab.nix { inherit shorthand; }).host;
      };
    };
}
