# Flake Optimization Design

## Summary

Refactor `dot.nix` to eliminate host file boilerplate, deduplicate identical host evals, and clean up accumulated dead code.

## A1: mkHost Helper Promotion

### Problem

5 host files (`m3pro.nix`, `callisto.nix`, `pluto.nix`, `x86-vps.nix`, `x86-vps-gpu.nix`) share ~80% identical boilerplate: `inherit` block, `homeManagerConfiguration` call, `modules` list, common HM modules.

The only meaningful differences per host:
- `system` (e.g. `aarch64-darwin`, `x86_64-linux`)
- `roles` (e.g. `["dev-core" "dev-extra" "top" "darwin-top"]`)
- `homeDirectory` (`/Users/charles` vs `/home/charles`)
- `targets` block (darwin / genericLinux / genericLinux-gpu / none)
- Optional `news.display`, `overlays`, `config` (nvidia)

### Design

Move `homeManagerConfiguration` construction into `flake.nix`'s `mkHost`. Delete `modules/hosts/` directory entirely.

**New `hosts.nix` schema:**

```nix
{
  "charles@m3pro" = {
    system = "aarch64-darwin";
    roles = [ "dev-core" "dev-extra" "top" "darwin-top" ];
    homeDirectory = "/Users/charles";
    target = "darwin";
  };
  "charles@callisto" = {
    system = "x86_64-linux";
    roles = [ "dev-core" "dev-extra" "top" "linux-top" ];
    homeDirectory = "/home/charles";
    target = "genericLinux";
  };
  "charles@pluto" = {
    system = "aarch64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    silent = true;
  };
  "charles@tmp-gpu" = {
    system = "x86_64-linux";
    roles = [ "dev-core" "dev-extra" "top" "linux-top" "nvidia-gpu" ];
    homeDirectory = "/home/charles";
    target = "genericLinux-gpu";
    gpu = true;
    silent = true;
  };

  # VPS hosts — all share the same config, listed as aliases
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    target = "genericLinux";
    silent = true;
    # Identical hosts share eval via sharedConfig (see B1)
    sharedConfig = "x86-vps";
  };
  # ... other VPS hosts with same sharedConfig = "x86-vps"
}
```

**New `mkHost` in `flake.nix`:**

```nix
mkHost = name: hostCfg:
  let
    enableSecrets = hostCfg.enableSecrets or true;
    isGpu = hostCfg.gpu or false;
    overlays = if isGpu then [ nixgl.overlay ] else [ ];
    pkgsConfig = { allowUnfree = true; }
      // (if isGpu then { nvidia.acceptLicense = true; } else { });

    targetModule =
      if hostCfg ? target then
        (if hostCfg.target == "genericLinux-gpu"
         then { targets.genericLinux = (import "${src}/modules/targets/genericLinux-gpu.nix" { inherit nixgl; }).genericLinux; }
         else { targets = { ${hostCfg.target} = (import "${src}/modules/targets/${hostCfg.target}.nix").${hostCfg.target}; }; })
      else { };

    silentModule =
      if hostCfg.silent or false then { news.display = "silent"; } else { };
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
      ({
        home = {
          username = "charles";
          homeDirectory = hostCfg.homeDirectory;
          stateVersion = hm_ver;
        };
      } // targetModule // silentModule)
    ];
  };
```

**Files deleted:** `modules/hosts/m3pro.nix`, `modules/hosts/callisto.nix`, `modules/hosts/pluto.nix`, `modules/hosts/x86-vps.nix`, `modules/hosts/x86-vps-gpu.nix`

**Files modified:** `flake.nix` (mkHost expanded), `hosts.nix` (new schema)

### `gpu-attr` / `base-attr` removal

The `base-attr` and `gpu-attr` intermediate attribute sets are no longer needed since `mkHost` directly references flake inputs. They are deleted from `flake.nix`.

## B1: Shared Eval for Identical Hosts

### Problem

8 VPS hosts (`RDSrv01`, `nics-demo-lab`, `nate-test`, `pg-proxy-dev`, `pg-primary-dev`, `pg-replica1-dev`, `pg-replica2-dev`, `testvm`) produce identical `homeManagerConfiguration` results. Each triggers a full eval.

### Design

Add a `sharedConfig` field to `hosts.nix`. Hosts with the same `sharedConfig` value reuse a single `homeManagerConfiguration` eval.

In `hosts.nix`, one host per shared group omits `sharedConfig` — this is the canonical definition that gets built. All others reference it by name:

```nix
# Canonical VPS config (built once)
"charles@RDSrv01" = {
  system = "x86_64-linux";
  roles = [ "dev-core" ];
  homeDirectory = "/home/charles";
  target = "genericLinux";
  silent = true;
};
# Shared aliases (reuse RDSrv01's eval)
"charles@nate-test" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
"charles@pg-proxy-dev" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
# ...
```

In `flake.nix`:

```nix
homeConfigurations =
  let
    directHosts = lib.filterAttrs (_: h: !(h ? sharedConfig)) hosts;
    sharedHosts = lib.filterAttrs (_: h: h ? sharedConfig) hosts;
    # Build each direct host once
    directConfigs = builtins.mapAttrs mkHost directHosts;
    # Map shared hosts to their canonical config
    sharedConfigs = lib.mapAttrs (_: hostCfg:
      directConfigs.${hostCfg.sharedConfig}
    ) sharedHosts;
  in
  directConfigs // sharedConfigs;
```

**Result:** Eval count drops from 12 to 5 (m3pro, callisto, pluto, x86-vps, tmp-gpu).

### CI Compatibility

The CI `eval-hosts` job filters by `hosts.${name}.system`. This still works since `hosts.nix` retains all host entries with their `system` field. The shared hosts will eval instantly (already cached by Nix's lazy evaluation).

## B2: Remove `programs.parallel` Duplicate

### Problem

`parallel` is in both `_common.nix` (as a package) and `core.nix` (as `programs.parallel` via HM module). Double installation.

### Change

Remove `inherit (import "${src}/modules/apps/parallel.nix") parallel;` from `core.nix` `programs` block. Delete `modules/apps/parallel.nix`. Keep `parallel` in `_common.nix`.

## C: Maintenance Cleanup

All changes below are independent and can be done in any order.

### C1: Remove `nur` comments

Remove all `# nur` / `# nur.overlays.default` / `# nur.modules.homeManager.default` references from:
- `flake.nix` (inputs, outputs, base-attr — 6 lines)
- All host files (removed by A1)

### C2: Delete `ssh-agent.nix`

Delete `modules/services/ssh-agent.nix`. Remove commented `# inherit ... ssh-agent` from `core.nix`. Cross-platform SSH agent is already handled by `addKeysToAgent = "yes"` in `ssh.nix`.

### C3: Remove dead app comments

Remove commented lines from `core.nix`:
- `# inherit (import "${src}/modules/apps/gcc.nix") gcc;`
- `# inherit (import "${src}/modules/apps/pistol.nix") pistol;`
- `# inherit (import "${src}/modules/apps/tirith.nix") tirith;`

### C4: Remove `autoExpire`

Remove `autoExpire` block from `modules/services/home-manager.nix`. `nh clean` (weekly, keep 5, keep-since 3d) handles GC.

### C5: Set `enableIonIntegration = false`

In `modules/apps/starship.nix`, set `enableIonIntegration = false` (was `true`, Ion shell not installed).

## Execution Order

1. **A1 + B1** — restructure `flake.nix` + `hosts.nix`, delete host files (biggest change, do first)
2. **B2** — remove `programs.parallel`
3. **C1-C5** — cleanup (independent, low risk)
4. **Validate** — `nix flake check` + eval all hosts

## Risk Assessment

- **A1 is the highest-risk change** — it restructures the flake's core wiring. Mitigation: eval every host after change, diff activation packages before/after.
- **B1 is medium-risk** — shared eval could mask host-specific issues. Mitigation: all shared hosts are truly identical (same `x86-vps.nix` today).
- **B2, C1-C5 are low-risk** — removing dead code or redundant config.
