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

    # Only used for `check` and `formatter` in flake.nix
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Nvidia GPU support for nix app on non-NixOS
    nixgl.url = "github:nix-community/nixGL";

    catppuccin.url = "github:catppuccin/nix/main";
    nix-filter.url = "github:numtide/nix-filter";
    snitch.url = "github:karol-broda/snitch";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      agenix,
      catppuccin,
      home-manager,
      nix-filter,
      nix-index-database,
      nixgl,
      nixpkgs,
      # nur,
      snitch,
      systems,
      treefmt-nix,
      ...
    }:
    let
      # Small tool to iterate over each systems
      eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});

      # Eval the treefmt modules from ./treefmt.nix
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);

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
        inherit
          base-attr
          nixgl
          ;
      };
    in
    {
      # for `nix fmt`
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
      # for `nix flake check`
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
      });

      filter = nix-filter.lib;
      source = src;

      # Define `homeModules`, `homeConfigurations`,
      # `nixosConfigurations`, etc here
      homeConfigurations = {
        "charles@m3pro" = (import ./modules/hosts/m3pro.nix { inherit base-attr; }).host;
        "charles@callisto" = (import ./modules/hosts/callisto.nix { inherit base-attr; }).host;
        "charles@pluto" = (import ./modules/hosts/pluto.nix { inherit base-attr; }).host;

        "charles@RDSrv01" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;

        "charles@nics-demo-lab" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
        "charles@nate-test" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
        "charles@tmp-gpu" = (import ./modules/hosts/x86-vps-gpu.nix { inherit gpu-attr; }).host;

        # dcf playground
        "charles@pg-proxy-dev" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
        "charles@pg-primary-dev" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
        "charles@pg-replica1-dev" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
        "charles@pg-replica2-dev" = (import ./modules/hosts/x86-vps.nix { inherit base-attr; }).host;
      };
    };
}
