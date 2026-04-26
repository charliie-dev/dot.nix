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

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixgl.url = "github:nix-community/nixGL";

    catppuccin.url = "github:catppuccin/nix/main";
    nix-filter.url = "github:numtide/nix-filter";
    snitch.url = "github:karol-broda/snitch";
    systems.url = "github:nix-systems/default";

    nix-src = {
      url = "github:DeterminateSystems/nix-src";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Used to re-evaluate nix-src flake outputs after locally patching
    # tests/functional/json.sh for util-linux 2.42 compatibility.
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      sops-nix,
      catppuccin,
      flake-compat,
      home-manager,
      nix-filter,
      nix-index-database,
      nix-src,
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
      inherit (nixpkgs) lib;

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

      mkHost =
        _name: hostCfg:
        let
          enableSecrets = hostCfg.enableSecrets or true;
          isGpu = hostCfg.gpu or false;
          # Patch nix-src tests/functional/json.sh: util-linux 2.42's `script`
          # rejects `script -e -q /dev/null -c CMD` (positional file before -c).
          # Only the -c branch needs reordering — the no-flag branch takes
          # `script ... file command ...`, which is BSD `script`'s required
          # syntax and is never reached on Linux (acceptsCommandFlag=1 there).
          # The grep assertion catches upstream drift loudly: if nix-src reflows
          # whitespace or quoting, the sed silently no-ops and the build would
          # fail 8 minutes later on the same json test — better to fail here.
          nixSrcPatched = nixpkgs.legacyPackages.${hostCfg.system}.applyPatches {
            name = "nix-src-utillinux-2.42-fix";
            src = nix-src;
            postPatch = ''
              sed -i \
                -e 's|script -e -q /dev/null -c "$(shellEscapeArray "$@")"|script -e -q -c "$(shellEscapeArray "$@")" /dev/null|' \
                tests/functional/json.sh
              grep -q 'script -e -q -c "$(shellEscapeArray "$@")" /dev/null' \
                tests/functional/json.sh \
                || { echo "nix-src json.sh patch did not match upstream — sed pattern needs updating" >&2; exit 1; }
            '';
          };
          nixSrcRebuilt = (import flake-compat { src = nixSrcPatched; }).defaultNix;
          nushellOverlay = _: prev: {
            nushell = prev.nushell.overrideAttrs (_: {
              doCheck = false;
            });
          };
          direnvOverlay = _: prev: {
            direnv = prev.direnv.overrideAttrs (_: {
              doCheck = false;
            });
          };
          neovimOverlay = _: prev: {
            neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (_: {
              doCheck = false;
              doInstallCheck = false;
            });
          };
          determinateNixOverlay = final: prev: {
            determinate-nix = nixSrcRebuilt.packages.${hostCfg.system}.default;
            nixos-option = prev.nixos-option.override { nix = final.determinate-nix; };
            nurl = prev.nurl.override { nix = final.determinate-nix; };
          };
          overlays = [
            nushellOverlay
            direnvOverlay
            neovimOverlay
            determinateNixOverlay
          ]
          ++ (if isGpu then [ nixgl.overlay ] else [ ]);
          pkgsConfig = {
            allowUnfree = true;
          }
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
            inherit (hostCfg) system;
            inherit overlays;
            config = pkgsConfig;
          };
          extraSpecialArgs = {
            inherit src enableSecrets;
            inherit (hostCfg) roles;
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
                  inherit (hostCfg) homeDirectory;
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

      homeConfigurations = directConfigs // sharedConfigs;
    };
}
