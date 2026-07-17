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

    # Declarative agent skills (SKILL.md dirs) synced to claude/codex/copilot/
    # opencode. google-skills is a plain skills repo (no flake.nix) consumed as
    # a source via flake=false; agent-skills resolves it through specialArgs.inputs.
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    google-skills = {
      url = "github:google/skills";
      flake = false;
    };

    catppuccin.url = "github:catppuccin/nix/main";
    nix-filter.url = "github:numtide/nix-filter";
    snitch.url = "github:karol-broda/snitch";
    systems.url = "github:nix-systems/default";

    nix-src = {
      url = "github:DeterminateSystems/nix-src";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      agent-skills,
      sops-nix,
      catppuccin,
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
          # Stub packages that delegate to upstream-tracked binaries kept in
          # $HOME/.local/share/<name>/bin/<name>. home-manager hardcodes
          # ${pkgs.<name>}/bin/<name> in places like `eval "$(.../mise activate zsh)"`,
          # so we keep a tiny Nix-managed wrapper for each tool and let the
          # DAG hooks in core.nix sync the actual binary with each switch.
          mkBinaryStub =
            prev: name:
            prev.writeShellScriptBin name ''
              exec -a "$(basename "$0")" "$HOME/.local/share/${name}/bin/${name}" "$@"
            '';
          binaryStubsOverlay = _: prev: {
            mise = mkBinaryStub prev "mise";
            topgrade = mkBinaryStub prev "topgrade";
          };
          # General rule: doCheck=false is only worth setting on a package we
          # are ALREADY forced to rebuild locally (e.g. the determinate-nix
          # override below pulls nurl off cache). On a package that still
          # substitutes from cache.nixos.org it just flips the hash and forces a
          # needless local rebuild — which is why there is no neovim overlay:
          # neovim-unwrapped is cached and a local rebuild is a heavy C compile.
          #
          # bat-extras.batman is the deliberate exception. Its derivation is
          # `dontBuild = 1` with an installPhase of `cp` + wrapProgram, so the
          # forced-local rebuild costs ~nothing. In return, doCheck=false drops
          # nushell/fish/zsh (batman's nativeCheckInputs) so they never land in
          # the /nix/store at all, even after a nixpkgs bump makes batman a
          # cache miss. We don't use nushell and don't want it pulled in.
          batExtrasOverlay = _: prev: {
            bat-extras = prev.bat-extras // {
              batman = prev.bat-extras.batman.overrideAttrs (_: {
                doCheck = false;
              });
            };
          };
          determinateNixOverlay =
            _final: prev:
            let
              # nix-src exposes its component scope as `nixComponents2` only via
              # the `internal` overlay (the public `default` overlay just sets a
              # nix-everything `nix`). Re-layer it onto our pkgs so components
              # build against our nixpkgs, then override the scope to drop the
              # wasmtime (Rust) compile: enableWasm only powers `builtins.wasm`
              # (call WebAssembly modules during eval), which we never use, and
              # wasmtime is a custom determinate build that is never cached.
              nixComponents = (prev.extend nix-src.overlays.internal).nixComponents2.overrideScope (
                _finalC: prevC: {
                  nix-expr = prevC.nix-expr.override { enableWasm = false; };
                  nix-store = prevC.nix-store.override { enableWasm = false; };
                }
              );
              # Use nix-cli, not nix-everything: nix-cli deliberately excludes
              # the C++ test suite (nix-expr-tests, nix-functional-tests, …),
              # which is never cached for our build and OOM-kills low-memory
              # hosts. nix-cli is also how upstream nixpkgs defines `nix`.
              #
              # Drop Sentry crash-reporting: it pulls sentry-native (bundles
              # crashpad) as an extra local C++ compile we don't want, and we
              # already disable Determinate telemetry at runtime. Both the
              # buildInput and the crashpad-handler mesonFlag must go — the flag
              # embeds ${sentry-native}, which alone would force the build.
              determinateNix = nixComponents.nix-cli.overrideAttrs (prevAttrs: {
                buildInputs = builtins.filter (
                  p: !(lib.hasInfix "sentry-native" (p.name or ""))
                ) prevAttrs.buildInputs;
                mesonFlags =
                  builtins.filter (
                    f: !(lib.hasInfix "sentry" f || lib.hasInfix "crashpad-handler" f)
                  ) prevAttrs.mesonFlags
                  ++ [ (lib.mesonEnable "sentry" false) ];
              });
            in
            {
              determinate-nix = determinateNix;
              nixos-option = prev.nixos-option.override { nix = determinateNix; };
              # nurl is forced local because of the nix override; skip its tests too.
              nurl = (prev.nurl.override { nix = determinateNix; }).overrideAttrs (_: {
                doCheck = false;
                doInstallCheck = false;
              });
            };
          overlays = [
            binaryStubsOverlay
            batExtrasOverlay
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
            inherit src enableSecrets inputs;
            inherit (hostCfg) roles;
          };
          modules = [
            "${src}/modules/core.nix"
            agent-skills.homeManagerModules.default
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
      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
      });

      homeConfigurations = directConfigs // sharedConfigs;
    };
}
