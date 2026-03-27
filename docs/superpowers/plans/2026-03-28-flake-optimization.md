# Flake Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate host file boilerplate, deduplicate identical host evals, and clean up dead code in the dot.nix Home Manager flake.

**Architecture:** Move `homeManagerConfiguration` construction entirely into `flake.nix`'s `mkHost`, driven by a declarative `hosts.nix` registry. Identical hosts share a single eval via `sharedConfig` references.

**Tech Stack:** Nix, Home Manager, Nix Flakes

**Spec:** `docs/superpowers/specs/2026-03-28-flake-optimization-design.md`

---

### Task 1: Rewrite `hosts.nix` to declarative schema

**Files:**
- Modify: `hosts.nix`

- [ ] **Step 1: Rewrite `hosts.nix` with new schema**

Replace the entire file. Each host declares `system`, `roles`, `homeDirectory`, and optional `target`, `gpu`, `silent`, `enableSecrets`, `sharedConfig` fields. Remove all `hostFile` references.

```nix
# hosts.nix — All host definitions in one place
# enableSecrets: per-host flag, set to false for first-time deploys on new machines
# sharedConfig: point to another host name to reuse its homeManagerConfiguration
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

  # Canonical VPS config (built once)
  "charles@RDSrv01" = {
    system = "x86_64-linux";
    roles = [ "dev-core" ];
    homeDirectory = "/home/charles";
    target = "genericLinux";
    silent = true;
  };
  # Shared aliases — reuse RDSrv01's eval result
  "charles@nics-demo-lab" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@nate-test" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@pg-proxy-dev" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@pg-primary-dev" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@pg-replica1-dev" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@pg-replica2-dev" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
  "charles@testvm" = { sharedConfig = "charles@RDSrv01"; system = "x86_64-linux"; };
}
```

- [ ] **Step 2: Commit**

```bash
git add hosts.nix
git commit -m "refactor(hosts): convert to declarative schema with sharedConfig support"
```

---

### Task 2: Rewrite `flake.nix` with new `mkHost` + shared eval (A1 + B1)

**Files:**
- Modify: `flake.nix`

This is the core change. The new `mkHost` reads the declarative `hosts.nix` fields directly and constructs `homeManagerConfiguration` inline — no more importing host files. The `base-attr` / `gpu-attr` intermediaries are removed. Shared hosts reuse a single eval.

- [ ] **Step 1: Rewrite `flake.nix`**

Replace the entire file with:

```nix
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
```

- [ ] **Step 2: Verify the flake parses**

Run: `nix flake show --no-write-lock-file 2>&1 | head -30`
Expected: `homeConfigurations` lists all 12 hosts without errors.

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "refactor(flake): inline mkHost, remove base-attr/gpu-attr, add shared eval"
```

---

### Task 3: Delete host files

**Files:**
- Delete: `modules/hosts/m3pro.nix`
- Delete: `modules/hosts/callisto.nix`
- Delete: `modules/hosts/pluto.nix`
- Delete: `modules/hosts/x86-vps.nix`
- Delete: `modules/hosts/x86-vps-gpu.nix`

- [ ] **Step 1: Delete all host files**

```bash
git rm modules/hosts/m3pro.nix modules/hosts/callisto.nix modules/hosts/pluto.nix modules/hosts/x86-vps.nix modules/hosts/x86-vps-gpu.nix
```

If the `modules/hosts/` directory is now empty, remove it:

```bash
rmdir modules/hosts 2>/dev/null || true
```

- [ ] **Step 2: Verify eval still works for darwin host**

Run: `nix eval .#homeConfigurations.\"charles@m3pro\".activationPackage.drvPath --raw && echo " OK"`
Expected: prints drv path followed by ` OK`

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: delete modules/hosts/ — mkHost handles all host construction"
```

---

### Task 4: Cleanup — remove `programs.parallel` duplicate (B2)

**Files:**
- Modify: `modules/core.nix` (remove one line)
- Delete: `modules/apps/parallel.nix`

- [ ] **Step 1: Remove `programs.parallel` from `core.nix`**

In `modules/core.nix`, delete this line from the `programs` block:

```
      inherit (import "${src}/modules/apps/parallel.nix") parallel;
```

Also remove the `will-cite` file entry from `home.file` since it was for `programs.parallel`:

Actually, keep the `will-cite` file — it suppresses the GNU Parallel citation notice and is needed regardless of how parallel is installed (package or program).

- [ ] **Step 2: Delete `modules/apps/parallel.nix`**

```bash
git rm modules/apps/parallel.nix
```

- [ ] **Step 3: Verify eval**

Run: `nix eval .#homeConfigurations.\"charles@m3pro\".activationPackage.drvPath --raw && echo " OK"`
Expected: prints drv path followed by ` OK`

- [ ] **Step 4: Commit**

```bash
git add modules/core.nix
git commit -m "fix: remove duplicate programs.parallel (kept in _common.nix as package)"
```

---

### Task 5: Cleanup — remove `nur` comments (C1)

**Files:**
- Modify: `flake.nix`

After A1, the host files are gone, so `nur` comments only remain in `flake.nix`.

- [ ] **Step 1: Remove all `nur` comments from `flake.nix`**

Remove these blocks/lines from `flake.nix`:

1. The commented `nur` input block (lines with `# NUR Community Packages`, `# nur = {`, etc.)
2. Any `# nur` in the outputs function args
3. Any `# nur.overlays.default` in the outputs

These were already removed in the Task 2 rewrite. Verify no `nur` references remain:

```bash
grep -n 'nur' flake.nix
```

Expected: no output

- [ ] **Step 2: Commit (if changes needed)**

```bash
git add flake.nix
git commit -m "chore: remove all commented nur references"
```

---

### Task 6: Cleanup — delete `ssh-agent.nix` + remove comment (C2)

**Files:**
- Delete: `modules/services/ssh-agent.nix`
- Modify: `modules/core.nix`

- [ ] **Step 1: Delete `ssh-agent.nix`**

```bash
git rm modules/services/ssh-agent.nix
```

- [ ] **Step 2: Remove commented ssh-agent line from `core.nix`**

In `modules/core.nix`, delete this line from the `services` block:

```
      # inherit (import "${src}/modules/services/ssh-agent.nix") ssh-agent;
```

- [ ] **Step 3: Commit**

```bash
git add modules/core.nix
git commit -m "chore: remove unused ssh-agent.nix service"
```

---

### Task 7: Cleanup — remove dead app comments from `core.nix` (C3)

**Files:**
- Modify: `modules/core.nix`

- [ ] **Step 1: Remove commented app lines**

In `modules/core.nix`, delete these three lines from the `programs` block:

```
      # inherit (import "${src}/modules/apps/gcc.nix") gcc;
      # inherit (import "${src}/modules/apps/pistol.nix") pistol;
      # inherit (import "${src}/modules/apps/tirith.nix") tirith;
```

- [ ] **Step 2: Commit**

```bash
git add modules/core.nix
git commit -m "chore: remove commented-out gcc/pistol/tirith app references"
```

---

### Task 8: Cleanup — remove `autoExpire` (C4)

**Files:**
- Modify: `modules/services/home-manager.nix`

- [ ] **Step 1: Remove `autoExpire` block**

Replace the entire file content with:

```nix
_: {
  home-manager = { };
}
```

The `home-manager` service remains enabled (it's the service entry), but `autoExpire` is removed. `nh clean` handles GC. Also fix the unused `config` argument — the file previously accepted `{ inherit config; }` from `core.nix` but never used it; change to `_:`.

- [ ] **Step 2: Update `core.nix` to match new arg signature**

In `modules/core.nix`, change:

```nix
      inherit (import "${src}/modules/services/home-manager.nix" { inherit config; }) home-manager;
```

to:

```nix
      inherit (import "${src}/modules/services/home-manager.nix" { }) home-manager;
```

- [ ] **Step 3: Verify eval**

Run: `nix eval .#homeConfigurations.\"charles@m3pro\".activationPackage.drvPath --raw && echo " OK"`
Expected: prints drv path followed by ` OK`

- [ ] **Step 4: Commit**

```bash
git add modules/services/home-manager.nix modules/core.nix
git commit -m "chore: remove autoExpire, nh clean handles GC"
```

---

### Task 9: Cleanup — set `enableIonIntegration = false` (C5)

**Files:**
- Modify: `modules/apps/starship.nix`

- [ ] **Step 1: Set `enableIonIntegration = false`**

In `modules/apps/starship.nix`, change:

```nix
    enableIonIntegration = true;
```

to:

```nix
    enableIonIntegration = false;
```

- [ ] **Step 2: Commit**

```bash
git add modules/apps/starship.nix
git commit -m "chore: disable Ion shell integration (not installed)"
```

---

### Task 10: Format + full validation

**Files:** All modified files

- [ ] **Step 1: Format all Nix files**

Run: `nix fmt`

- [ ] **Step 2: Commit formatting if changed**

```bash
git add -A
git commit -m "style: apply treefmt formatting" || true
```

- [ ] **Step 3: Run flake check**

Run: `nix flake check`
Expected: no errors

- [ ] **Step 4: Evaluate all non-GPU, non-cross-arch hosts**

The darwin host (`charles@m3pro`) can only be evaluated on macOS. Evaluate the hosts that match the current system:

```bash
for host in "charles@m3pro"; do
  echo -n "Evaluating $host... "
  nix eval .#homeConfigurations.\"$host\".activationPackage.drvPath --raw && echo " OK" || echo " FAIL"
done
```

On macOS, only `charles@m3pro` will succeed locally. The Linux hosts require a Linux evaluator (CI handles this).

- [ ] **Step 5: Verify shared hosts resolve correctly**

```bash
canonical=$(nix eval .#homeConfigurations.\"charles@RDSrv01\".activationPackage.drvPath --raw 2>/dev/null || echo "SKIP")
if [ "$canonical" != "SKIP" ]; then
  alias=$(nix eval .#homeConfigurations.\"charles@testvm\".activationPackage.drvPath --raw)
  if [ "$canonical" = "$alias" ]; then
    echo "Shared eval OK: RDSrv01 == testvm"
  else
    echo "FAIL: shared configs produced different drv paths"
    exit 1
  fi
fi
```

Expected (on Linux): `Shared eval OK: RDSrv01 == testvm`
Expected (on macOS): skipped (cross-system eval not available)
