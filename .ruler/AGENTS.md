## Architecture

Nix Home-Manager dotfiles repo — manages dev environments across macOS/Linux using Nix Flakes.

- `flake.nix` - Inputs and homeConfigurations per host
- `hosts.nix` - Declarative host registry (system, roles, targets, sharedConfig)
- `modules/core.nix` - Aggregates program fragments and owns shared Home Manager policy
- `modules/runtime/*.nix` - App-specific activation hooks; `modules/platform.nix` owns OS-specific services
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
- Exception: the secret-gated Doppler loader is `programs.zsh.envExtra` in `modules/doppler.nix`.

Keep it simple: max 3 levels of indentation. Never break existing functionality.
