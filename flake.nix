{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # nixpkgs-unstable

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR Community Packages
    nur = {
      url = "github:nix-community/NUR";
      # Requires "nur.modules.nixos.default" to be added to the host modules
    };

    # Fixes OpenGL With Other Distros.
    nixgl = {
      url = "github:guibou/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix/main";
    nix-formatter-pack.url = "github:Gerschtli/nix-formatter-pack";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nixgl,
      catppuccin,
      nix-formatter-pack,
      nur,
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
      base-attr = {
        inherit home-manager;
        hm_ver = "25.11";
        inherit nixpkgs;
        inherit nur;
        inherit catppuccin;
      };
      nixgl-attr = base-attr // {
        inherit nixgl;
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
        "charles@m3pro.local" = (import ./modules/hosts/m3pro.nix { inherit base-attr; }).host;
        "charles@callisto" = (import ./modules/hosts/callisto.nix { inherit nixgl-attr; }).host;
        "charles@RDSrv01" = (import ./modules/hosts/rdsrv01.nix { inherit base-attr; }).host;
        "charles@bot" = (import ./modules/hosts/oc_bot.nix { inherit base-attr; }).host;
        "charles@nics-demo-lab" = (import ./modules/hosts/nics-demo-lab.nix { inherit base-attr; }).host;
      };
    };
}
