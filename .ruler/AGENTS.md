## Architecture

Nix Home-Manager dotfiles repo — manages dev environments across macOS/Linux using Nix Flakes.

- `flake.nix` - Inputs and homeConfigurations per host
- `hosts.nix` - Declarative host registry (system, roles, targets, sharedConfig)
- `modules/core.nix` - Aggregates all programs; each app has its own module
- Role-based packages: hosts.nix defines roles → `modules/apps/roles/*.nix`
- DAG activation: `lib.hm.dag.entryAfter ["writeBoundary"]`
- Custom scripts: `conf.d/Usercommand/` → `~/.local/bin`
- Secrets: `sops-nix` + Doppler

Keep it simple: max 3 levels of indentation. Never break existing functionality.
