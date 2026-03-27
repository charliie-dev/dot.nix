{
  description = "Home Manager configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix.url = "github:numtide/treefmt-nix";

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
      snitch,
      systems,
      treefmt-nix,
      ...
    }:
    let
      eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
      lib = nixpkgs.lib;

      src = nix-filter.lib.filter {
        root = ./.;
        include = [
          "conf.d"
          "modules"
          "flake.nix"
          "hosts.nix"
        ];
      };

      hm_ver = "26.05";
      hosts = import ./hosts.nix;

      mkHost = _name: hostCfg:
        let
          enableSecrets = hostCfg.enableSecrets or true;
          isGpu = hostCfg.gpu or false;
          overlays = if isGpu then [ nixgl.overlay ] else [ ];
          pkgsConfig = { allowUnfree = true; }
            // (if isGpu then { nvidia.acceptLicense = true; } else { });

          targetModule =
            if hostCfg ? target then
              (
                if hostCfg.target == "genericLinux-gpu" then
                  {
                    targets.genericLinux =
                      (import "${src}/modules/targets/genericLinux-gpu.nix" { inherit nixgl; }).genericLinux;
                  }
                else
                  {
                    targets.${hostCfg.target} =
                      (import "${src}/modules/targets/${hostCfg.target}.nix").${hostCfg.target};
                  }
              )
            else
              { };

          silentModule = if hostCfg.silent or false then { news.display = "silent"; } else { };
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = hostCfg.system;
            inherit overlays;
            config = pkgsConfig;
          };
          extraSpecialArgs = {
            inherit src enableSecrets;
            roles = hostCfg.roles;
          };
          modules = [
            "${src}/modules/core.nix"
            sops-nix.homeManagerModules.sops
            catppuccin.homeModules.catppuccin
            nix-index-database.homeModules.nix-index
            snitch.homeManagerModules.default
            (
              {
                home = {
                  username = "charles";
                  homeDirectory = hostCfg.homeDirectory;
                  stateVersion = hm_ver;
                };
              }
              // targetModule
              // silentModule
            )
          ];
        };

      # B1: Shared eval — build direct hosts once, alias shared hosts
      directHosts = lib.filterAttrs (_: h: !(h ? sharedConfig)) hosts;
      sharedHosts = lib.filterAttrs (_: h: h ? sharedConfig) hosts;
      directConfigs = builtins.mapAttrs mkHost directHosts;
      sharedConfigs = lib.mapAttrs (_: hostCfg: directConfigs.${hostCfg.sharedConfig}) sharedHosts;
    in
    {
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
      });

      filter = nix-filter.lib;
      source = src;

      homeConfigurations = directConfigs // sharedConfigs;
    };
}
