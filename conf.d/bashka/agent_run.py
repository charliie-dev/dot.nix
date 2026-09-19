"""Fixed native Bashka invocation; arguments belong only to the installer."""

import os
import sys

BINARY = "@binary@"
POLICY = "@policy@"
BASH_BIN = "@bashBin@"
STARTUP = {"BASH_ENV", "ENV", "BASHOPTS", "SHELLOPTS", "CDPATH", "GLOBIGNORE"}


def environment(inherited):
    clean = {
        key: value
        for key, value in inherited.items()
        if key not in STARTUP
        and not key.startswith(("BASHFLAGS_", "BASH_FUNC_", "DYLD_", "LD_"))
    }
    clean["PATH"] = BASH_BIN + os.pathsep + clean.get("PATH", "/usr/bin:/bin")
    clean["BASHFLAGS_REAL_PATH"] = clean["PATH"]
    return clean


def main():
    argv = [BINARY, "--non-interactive", "--config", POLICY, "--", "--", *sys.argv[1:]]
    try:
        os.execve(BINARY, argv, environment(os.environ))
    except OSError:
        print(
            "Bashka entry could not execute the installed binary; no shell fallback.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
