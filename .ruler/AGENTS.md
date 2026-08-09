## Architecture

Nix Home-Manager dotfiles repo — manages dev environments across macOS/Linux using Nix Flakes.

- `flake.nix` - Inputs and homeConfigurations per host
- `hosts.nix` - Declarative host registry (system, roles, gpu, sharedConfig)
- `modules/default.nix` - Entry point for all local Home Manager modules
- `modules/core.nix` - Shared Nix, XDG, environment, PATH, and Home Manager policy
- `modules/apps/default.nix` - Aggregates program fragments, full app modules, and role-based packages
- `modules/runtime/*.nix` - App-specific activation hooks
- `modules/platform/*.nix` - OS targets, runtime integration, and platform services
- `modules/secrets/*.nix` - Secret-gated SOPS and Doppler integration
- Role-based packages: hosts.nix defines roles → `modules/apps/roles/*.nix`
- `skills/` - Version-controlled agent skill sources; not Home Manager modules
- DAG activation: `lib.hm.dag.entryAfter ["writeBoundary"]`
- Custom scripts: `conf.d/Usercommand/` → `~/.local/bin`
- Secrets: `sops-nix` + Doppler via `modules/secrets/*.nix`

### Shell configuration ownership

- Zsh-specific configuration: `modules/apps/zsh/*.nix`
- Cross-shell environment variables and PATH: `modules/core.nix`
- Program-generated shell integrations: `modules/apps/<program>.nix`
- macOS GUI/launchd environment: `modules/platform/services/brew-env.nix` (not shell RC)
- Generated Zsh RC files are `.zshenv`, `.zprofile`, and `.zshrc`; do not reintroduce runtime `conf.d/zsh/*.zsh` sources.
- Exception: the secret-gated Doppler loader is `programs.zsh.envExtra` in `modules/secrets/doppler.nix`.

Keep it simple: max 3 levels of indentation. Never break existing functionality.
