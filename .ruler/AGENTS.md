## Architecture

Nix Home-Manager dotfiles repository (`dot.nix`) — manages dev environments across macOS/Linux using Nix Flakes.

### Entry Points

- `flake.nix` - Defines all inputs and homeConfigurations for each host
- `modules/core.nix` - Universal module aggregating all programs, services, and packages
- `hosts.nix` - Declarative host registry (system, roles, targets, sharedConfig)

### Key Patterns

- **Role-Based Packages**: hosts.nix defines roles → `modules/apps/roles/*.nix` loads corresponding packages
- **Modular Programs**: Each app has its own module, imported in core.nix via `inherit`
- **DAG Activation**: Uses `lib.hm.dag.entryAfter ["writeBoundary"]` to order activation scripts

### Key Directories

- `modules/apps/roles/` - Role-based package sets (dev-core, dev-extra, darwin-top, etc.)
- `conf.d/Usercommand/` - Custom scripts deployed to `~/.local/bin`
- Secrets: `sops-nix` (`modules/sops.nix`) + Doppler (`modules/doppler.nix`)

### Mise

This project uses mise to manage tools, env vars, and tasks. MCP resources available:

- `mise://env` - Environment variables
- `mise://tools` - Managed tool versions
- `mise://tasks` - Project tasks (e.g. `ruler`, `nhsw`, `add-host`)
- `mise://config` - Mise configuration

## Development Philosophy

- **Pragmatism over theory**: Solve real problems, not imaginary threats
- **Simplicity**: If implementation needs more than 3 levels of indentation, redesign it
- **Backward compatibility**: Never break existing functionality; any change that causes existing programs to fail is a bug
- **Good taste**: Eliminate edge cases through better design rather than adding conditional checks
