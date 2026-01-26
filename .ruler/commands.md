## Common Commands

**IMPORTANT**: After making ANY changes to `.nix` files, you MUST run the `/validate` skill to verify the configuration works correctly. If validation fails, analyze the error and fix it before proceeding.

```sh
# Validate configuration
nix flake check

# Evaluate specific host configuration (detailed validation)
nix eval .#homeConfigurations.$USER@$(hostname).activationPackage --show-trace

# Build with verbose output (useful for debugging)
home-manager build -v --show-trace --option eval-cache false

# Apply configuration
home-manager switch --flake .
# Or using nh (preferred):
nh home switch

# Update flake inputs
nix flake update

# Format code
nix fmt

# Garbage collection
nh clean all --ask
```
