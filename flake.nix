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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      sops-nix,
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
          "hosts.nix"
        ];
      };

      hosts = import ./hosts.nix;

      base-attr = {
        hm_ver = "26.05";
        inherit
          sops-nix
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

      mkHost =
        _name: hostCfg:
        let
          enableSecrets = hostCfg.enableSecrets or true;
          hostArgs =
            if hostCfg.gpu or false then
              {
                gpu-attr = gpu-attr // {
                  base-attr = gpu-attr.base-attr // {
                    inherit enableSecrets;
                  };
                };
              }
            else
              {
                base-attr = base-attr // {
                  inherit enableSecrets;
                };
              };
        in
        (import hostCfg.hostFile hostArgs).host;
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

      homeConfigurations = builtins.mapAttrs mkHost hosts;
    };
}
