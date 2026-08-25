## Architecture

Nix Home-Manager dotfiles repo — manages dev environments across macOS/Linux using Nix Flakes.

- `flake.nix` - Inputs and homeConfigurations per host
- `hosts.nix` - Declarative host registry (system, roles, nvidiaGpu, sharedConfig)
- `modules/default.nix` - Entry point for all local Home Manager modules
- `modules/core.nix` - Shared Nix, XDG, environment, PATH, and Home Manager policy
- `modules/apps/default.nix` - Aggregates program fragments, full app modules, and role-based packages
- `modules/runtime/*.nix` - App-specific activation hooks
- `modules/platform/*.nix` - OS targets, runtime integration, and platform services
- `modules/secrets/*.nix` - Secret-gated SOPS and Doppler integration
- Package catalog: `modules/apps/_packages.nix` defines common and role-based packages selected by `hosts.nix`
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

## Language tooling

For every changed supported file, use the matching LSP diagnostics while editing, apply its configured formatter, and run its linters. Completion requires a clean formatter result and no unexplained LSP or linter diagnostics.

- Nix: `nixd` or `nil`, then `nixfmt`, `deadnix`, and `statix`.
- Shell: `shuck`, then `shellharden` and `shellcheck`.
- GitHub Actions: `gh_actions_ls`, then `actionlint`, `shuck`, and `zizmor`.
- Dockerfiles: `dockerls`, then `hadolint` and `droast`.
- TOML: `tombi` for language support and formatting.
- Run `mise run fmt` and `mise run ci` for repository-wide Nix verification.

Tool ownership lives in `modules/apps/_packages.nix` and `modules/apps/mise.nix`; keep those declarations aligned with `~/.config/nvim/lua/core/settings.lua`. Mason is not a package provider.

Keep it simple: max 3 levels of indentation. Never break existing functionality.
