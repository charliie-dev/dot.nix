## Architecture

Nix Home-Manager dotfiles repo — manages dev environments across macOS/Linux using Nix Flakes.

- `flake.nix` - Inputs and homeConfigurations per host
- `hosts.nix` - Declarative host registry (system, roles, targets, sharedConfig)
- `modules/core.nix` - Aggregates all programs; each app has its own module
- Role-based packages: hosts.nix defines roles → `modules/apps/roles/*.nix`
- DAG activation: `lib.hm.dag.entryAfter ["writeBoundary"]`
- Custom scripts: `conf.d/Usercommand/` → `~/.local/bin`
- Secrets: `sops-nix` + Doppler

### Shell configuration ownership

- Zsh-specific configuration: `modules/apps/zsh/*.nix`
- Cross-shell environment variables and PATH: `modules/core.nix`
- Program-generated shell integrations: `modules/apps/<program>.nix`
- macOS GUI/launchd environment: `modules/services/brew-env.nix` (not shell RC)
- Generated Zsh RC files are `.zshenv`, `.zprofile`, and `.zshrc`; do not reintroduce runtime `conf.d/zsh/*.zsh` sources.
- Exception: the secret-gated Doppler loader remains as `programs.zsh.envExtra` in `modules/core.nix`.

Keep it simple: max 3 levels of indentation. Never break existing functionality.
