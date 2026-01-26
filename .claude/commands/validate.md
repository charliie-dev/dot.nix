# Validate Home Manager Configuration

This skill validates the Home Manager configuration after any changes are made to the codebase.

## Instructions

You MUST run this skill after making ANY changes to nix files in this repository.

### Step 1: Run validation

Execute the following command to validate and apply the configuration:

```bash
home-manager switch --show-trace --verbose 2>&1
```

### Step 2: Analyze the result

- If the command succeeds (exit code 0), report success to the user
- If the command fails (exit code non-zero), analyze the error message

### Step 3: Fix errors (if any)

Common error patterns and fixes:

1. **Syntax errors**: Look for line numbers in the error trace, read the file, and fix the syntax
2. **Type errors** (e.g., "expected a list but found..."): Check function signatures and ensure correct argument passing
3. **Missing attributes**: Verify that all referenced attributes exist in the scope
4. **Evaluation errors**: Check `let` bindings and function definitions

After fixing, re-run the validation command to verify the fix works.

### Step 4: Report

Provide a summary:
- What was validated
- Whether it succeeded or failed
- What fixes were applied (if any)
