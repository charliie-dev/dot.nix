{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # nixpkgs-unstable

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR Community Packages
    # nur = {
    #   url = "github:nix-community/NUR";
    #   # Requires "nur.modules.nixos.default" to be added to the host modules
    # };

    # Weekly updated nix-index database
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret Management
    agenix.url = "github:ryantm/agenix";

    catppuccin.url = "github:catppuccin/nix/main";
    nix-filter.url = "github:numtide/nix-filter";
    nix-formatter-pack.url = "github:Gerschtli/nix-formatter-pack";
    nixgl.url = "github:nix-community/nixGL";
    snitch.url = "github:karol-broda/snitch";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      # nur,
      nix-index-database,
      agenix,
      catppuccin,
      nix-filter,
      nix-formatter-pack,
      nixgl,
      snitch,
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

      nixfmtpack = nix-formatter-pack;

      src = nix-filter.lib.filter {
        root = ./.;
        include = [
          "conf.d"
          "modules"
          "flake.nix"
        ];
      };

      base-attr = {
        hm_ver = "26.05";
        inherit
          agenix
          catppuccin
          home-manager
          nix-index-database
          nixpkgs
          # nur
          snitch
          src
          ;
      };

      gpu-attr = {
        hm_ver = "26.05";
        inherit
          agenix
          catppuccin
          home-manager
          nix-index-database
          nixgl
          nixpkgs
          # nur
          src
          ;
      };
    in
    {
      checks = forEachSystem (system: {
        nix-formatter-pack-check = nixfmtpack.lib.mkCheck formatterPackArgsPerSystem.${system};
      });

      formatter = forEachSystem (system: nixfmtpack.lib.mkFormatter formatterPackArgsPerSystem.${system});

      filter = nix-filter.lib;
      source = src;

      # Define `homeModules`, `homeConfigurations`,
      # `nixosConfigurations`, etc here
      homeConfigurations = {
        "charles@m3pro" = (import ./modules/hosts/m3pro.nix { inherit base-attr; }).host;
        "charles@callisto" = (import ./modules/hosts/callisto.nix { inherit base-attr; }).host;
        "charles@bot" = (import ./modules/hosts/oc_bot.nix { inherit base-attr; }).host;
        "charles@RDSrv01" = (import ./modules/hosts/rdsrv01.nix { inherit base-attr; }).host;

        "charles@nics-demo-lab" = (import ./modules/hosts/nics-demo-lab.nix { inherit base-attr; }).host;
        "charles@nate-test" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@tmp-gpu" = (import ./modules/hosts/dcf-gpu.nix { inherit gpu-attr; }).host;

        # dcf playground
        "charles@dcf-demo" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@pg-cluster" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@nats-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@etcd-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@haproxy-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@pg-primary-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@pg-replica1-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@pg-replica2-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@agent1-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@agent2-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
        "charles@platform-dev" = (import ./modules/hosts/dcf-demo.nix { inherit base-attr; }).host;
      };
    };
}
