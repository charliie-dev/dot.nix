## Architecture

### Entry Points

- `flake.nix` - Defines all inputs and homeConfigurations for each host
- `modules/core.nix` - Universal module aggregating all programs, services, and packages
- `secrets.nix` - Age-encrypted secrets mapping (works with `modules/agenix.nix`)

### Key Patterns

**Role-Based Package Management**: Hosts define roles that conditionally load packages:

```nix
# In host config (modules/hosts/*.nix):
roles = [ "dev-core" "dev-extra" "top" "darwin-top" ];

# Roles are defined in modules/apps/roles/*.nix
```

**Modular Program Configuration**: Each app has its own module exporting a single attribute:

```nix
# modules/apps/gh.nix
{ pkgs, ... }:
{
  gh = {
    enable = true;
    extensions = with pkgs; [ ... ];
  };
}

# Imported in core.nix via:
inherit (import "${src}/modules/apps/gh.nix" { inherit pkgs; }) gh;
```

**DAG Activation Scripts**: Home Manager activation with explicit ordering:

```nix
activation = {
  myScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''...'';
};
```

### Directory Structure

- `modules/apps/` - Individual program configurations (`programs.*`)
- `modules/apps/roles/` - Role-based package sets (dev-core, dev-extra, darwin-top, etc.)
- `modules/apps/_common.nix` - Packages included on all hosts
- `modules/hosts/` - Host-specific configurations defining system, roles, and username
- `modules/targets/` - OS-specific configs (darwin.nix, genericLinux.nix)
- `modules/services/` - Service configurations (`services.*`)
- `conf.d/` - Runtime config files (zsh scripts, tmux configs, encrypted secrets)
- `conf.d/Usercommand/` - Custom scripts deployed to `~/.local/bin`
- `conf.d/ages/` - Age-encrypted secret files

### Secrets Management

Secrets are managed via `agenix`. Public keys are defined in `secrets.nix`, encrypted files live in `conf.d/ages/`, and decryption is configured in `modules/agenix.nix`.
