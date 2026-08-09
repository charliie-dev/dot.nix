{
  config,
  pkgs,
  lib,
  enableSecrets ? false,
  ...
}:
let
  dopplerDir = "${config.xdg.dataHome}/doppler";
  dopplerTokenPath = "${dopplerDir}/token";
  dopplerTokenTarget = "${config.xdg.configHome}/sops-nix/secrets/doppler_token";
  sensitiveNames = [
    "DOPPLER_TOKEN"
    "DOPPLER_PROJECT"
    "DOPPLER_CONFIG"
    "DOPPLER_ENVIRONMENT"
    "AZURE_OPENAI_API_KEY"
    "AZURE_OPENAI_BASE_URL"
    "AZURE_OPENAI_DEPLOYMENT_NAME_MAP"
    "AZURE_OPENAI_API_ENDPOINT"
    "TSTRUCT_TOKEN"
    "CLAUDE_CODE_OAUTH_TOKEN"
    "CF_TOKEN_CHARLIIE_RO"
    "CF_TOKEN_ANMO_RO"
    "CF_API_TOKEN"
    "CLOUDFLARE_API_TOKEN"
    "CF_ACCOUNT_ID"
    "CLOUDFLARE_ACCOUNT_ID"
    "CF_ZONE_ID"
    "CF_ZONE_NAME"
  ];
  dopplerRun = pkgs.writeShellApplication {
    name = "doppler-run";
    runtimeInputs = [
      pkgs.doppler
      pkgs.python3
    ];
    text = ''
      exec python3 ${pkgs.writeText "doppler-run.py" ''
        import base64
        import os
        import re
        import signal
        import stat
        import sys
        import tomllib
        from urllib.parse import urlsplit

        TOKEN_PATH = ${builtins.toJSON dopplerTokenPath}
        TOKEN_TARGET = ${builtins.toJSON dopplerTokenTarget}
        GROK_CONFIG = ${builtins.toJSON "${config.xdg.configHome}/grok/config.toml"}
        SENSITIVE = set(${builtins.toJSON sensitiveNames})
        BOOTSTRAP_METADATA = {
            "DOPPLER_PROJECT",
            "DOPPLER_CONFIG",
            "DOPPLER_ENVIRONMENT",
        }
        SANITIZE = SENSITIVE | {"DOPPLER_CONFIG_DIR"}
        PROFILES = {
            "azure-grok": ("AZURE_OPENAI_API_KEY",),
            "azure-codex": ("AZURE_OPENAI_API_KEY",),
            "azure-pi": (
                "AZURE_OPENAI_API_KEY",
                "AZURE_OPENAI_BASE_URL",
                "AZURE_OPENAI_DEPLOYMENT_NAME_MAP",
            ),
            "claude-oauth": ("CLAUDE_CODE_OAUTH_TOKEN",),
            "cloudflare-charliie": ("CF_TOKEN_CHARLIIE_RO",),
            "cloudflare-anmo": ("CF_TOKEN_ANMO_RO",),
        }
        CF = {
            "cloudflare-charliie": (
                "CF_TOKEN_CHARLIIE_RO",
                "864dd04341d2aca5804853428630fbc4",
                "81b636594b5278a3f8c9d7e386b71f3c",
                "charliie.dev",
            ),
            "cloudflare-anmo": (
                "CF_TOKEN_ANMO_RO",
                "8970faafb1d450c722678d598a626820",
                "3013ec25b311952bdab9e8284c6ca79a",
                "anmo.tw",
            ),
        }
        GROK_EXCLUDES = SENSITIVE
        NAME_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
        CF_TOKEN_RE = re.compile(r"^[0-9A-Za-z_-]{40,80}$")

        def fail(message):
            print(f"doppler-run: {message}", file=sys.stderr)
            raise SystemExit(1)

        def safe_regular(path, exact_mode=None):
            try:
                st = os.lstat(path)
            except OSError:
                fail("required private file is unavailable")
            if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
                fail("private file has an unsafe type")
            if st.st_uid != os.getuid():
                fail("private file has an unexpected owner")
            if exact_mode is not None and stat.S_IMODE(st.st_mode) != exact_mode:
                fail("private file has an unsafe mode")
            return st

        def validate_private_parents(path):
            home = os.path.abspath(os.path.expanduser("~"))
            target = os.path.abspath(path)
            if os.path.commonpath((home, target)) != home:
                fail("private path is outside the home directory")
            current = home
            for part in os.path.relpath(os.path.dirname(target), home).split(os.sep):
                if part == ".":
                    continue
                current = os.path.join(current, part)
                try:
                    st = os.lstat(current)
                except OSError:
                    fail("private directory is unavailable")
                if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                    fail("private directory has an unsafe type")
                if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o022:
                    fail("private directory has unsafe ownership or mode")

        def open_expected_link(path, expected_target, exact_mode):
            try:
                link_st = os.lstat(path)
            except OSError:
                fail("required deployment link is unavailable")
            if not stat.S_ISLNK(link_st.st_mode) or link_st.st_uid != os.getuid():
                fail("deployment path is not the expected owned symlink")
            try:
                link_value = os.readlink(path)
            except OSError:
                fail("deployment link cannot be read safely")
            if link_value != expected_target:
                fail("deployment link has an unexpected target")
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(expected_target, flags)
            except OSError:
                fail("terminal secret file cannot be opened safely")
            st = os.fstat(fd)
            if (
                not stat.S_ISREG(st.st_mode)
                or st.st_uid != os.getuid()
                or stat.S_IMODE(st.st_mode) != exact_mode
            ):
                os.close(fd)
                fail("terminal secret file has unsafe owner, type, or mode")
            return fd

        def read_token():
            validate_private_parents(TOKEN_PATH)
            fd = open_expected_link(TOKEN_PATH, TOKEN_TARGET, 0o400)
            try:
                chunks = []
                total = 0
                while True:
                    chunk = os.read(fd, 8192)
                    if not chunk:
                        break
                    chunks.append(chunk)
                    total += len(chunk)
                    if total > 65536:
                        fail("token file is unexpectedly large")
            finally:
                os.close(fd)
            try:
                token = b"".join(chunks).decode("utf-8")
            except UnicodeDecodeError:
                fail("token file is not valid UTF-8")
            if not token or any(c in token for c in "\x00\r\n"):
                fail("token file has an invalid encoding")
            return token

        def validate_grok_policy():
            safe_regular(GROK_CONFIG)
            try:
                with open(GROK_CONFIG, "rb") as handle:
                    doc = tomllib.load(handle)
            except (OSError, tomllib.TOMLDecodeError):
                fail("Grok config is unreadable or malformed")
            policy = doc.get("shell_environment_policy")
            if not isinstance(policy, dict) or set(policy) != {
                "inherit", "ignore_default_excludes", "exclude"
            }:
                fail("Grok shell environment policy has drifted")
            excludes = policy.get("exclude")
            if (
                policy.get("inherit") != "core"
                or policy.get("ignore_default_excludes") is not False
                or not isinstance(excludes, list)
                or any(not isinstance(x, str) for x in excludes)
                or len(excludes) != len(set(excludes))
                or set(excludes) != GROK_EXCLUDES
            ):
                fail("Grok shell environment policy has drifted")

        def clean_environment(source):
            return {k: v for k, v in source.items() if k not in SANITIZE}

        def validate_value(name, value):
            if not NAME_RE.fullmatch(name) or not value or any(c in value for c in "\x00\r\n"):
                fail("injected profile data failed validation")

        def validate_pi(env):
            parsed = urlsplit(env["AZURE_OPENAI_BASE_URL"])
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                fail("Azure base URL failed validation")
            seen = set()
            entries = env["AZURE_OPENAI_DEPLOYMENT_NAME_MAP"].split(",")
            if not entries:
                fail("Azure deployment map failed validation")
            for entry in entries:
                if entry.count("=") != 1:
                    fail("Azure deployment map failed validation")
                model, deployment = (part.strip() for part in entry.split("=", 1))
                if (
                    not model
                    or not deployment
                    or model in seen
                    or any(ch.isspace() or ord(ch) < 0x20 or ord(ch) == 0x7f for ch in model + deployment)
                ):
                    fail("Azure deployment map failed validation")
                seen.add(model)

        def launch(profile, command):
            required = set(PROFILES[profile])
            boundary = required | {"DOPPLER_TOKEN"} | BOOTSTRAP_METADATA
            present = {name for name in SANITIZE if name in os.environ}
            if present != boundary:
                fail("injected profile key set is not exact")
            for name in boundary:
                validate_value(name, os.environ[name])
            if (
                os.environ["DOPPLER_PROJECT"] != "dot-nix"
                or os.environ["DOPPLER_CONFIG"] != "dev_personal"
            ):
                fail("injected Doppler source metadata does not match fixed source")
            final = clean_environment(os.environ)
            for name in required:
                final[name] = os.environ[name]
            if profile == "azure-pi":
                validate_pi(final)
            if profile in CF:
                source, account, zone, zone_name = CF[profile]
                token = final.pop(source)
                if not CF_TOKEN_RE.fullmatch(token):
                    fail("Cloudflare token failed validation")
                final.update({
                    "CF_API_TOKEN": token,
                    "CLOUDFLARE_API_TOKEN": token,
                    "CF_ACCOUNT_ID": account,
                    "CLOUDFLARE_ACCOUNT_ID": account,
                    "CF_ZONE_ID": zone,
                    "CF_ZONE_NAME": zone_name,
                })
            final_managed = set(final).intersection(SENSITIVE)
            expected = required if profile not in CF else {
                "CF_API_TOKEN", "CLOUDFLARE_API_TOKEN", "CF_ACCOUNT_ID",
                "CLOUDFLARE_ACCOUNT_ID", "CF_ZONE_ID", "CF_ZONE_NAME",
            }
            if final_managed != expected or "DOPPLER_TOKEN" in final:
                fail("target managed environment is not exact")
            os.execvpe(command[0], command, final)

        def main():
            if len(sys.argv) >= 2 and sys.argv[1] == "--internal-launch":
                if len(sys.argv) < 5 or sys.argv[3] != "--" or sys.argv[2] not in PROFILES:
                    fail("invalid internal invocation")
                launch(sys.argv[2], sys.argv[4:])
            if len(sys.argv) < 4 or sys.argv[2] != "--" or sys.argv[1] not in PROFILES:
                fail("usage: doppler-run <fixed-profile> -- <command> [args...]")
            profile = sys.argv[1]
            command = sys.argv[3:]
            if profile == "azure-grok":
                validate_grok_policy()
            token = read_token()
            env = clean_environment(os.environ)
            env["DOPPLER_TOKEN"] = token
            argv = [
                "${pkgs.doppler}/bin/doppler", "run", "--no-fallback",
                "--project", "dot-nix", "--config", "dev_personal",
            ]
            for name in PROFILES[profile]:
                argv.extend(("--only-secrets", name))
            argv.extend(("--", sys.executable, os.path.realpath(__file__),
                         "--internal-launch", profile, "--", *command))
            os.execve(argv[0], argv, env)

        if __name__ == "__main__":
            main()
      ''} "$@"
    '';
  };
  wrapper =
    name: profile: command: extraArgs:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${dopplerRun}/bin/doppler-run ${profile} -- ${command} ${extraArgs} "$@"
      '';
    };
  codexAzure = pkgs.writeShellApplication {
    name = "codex-azure";
    text = ''
      for arg in "$@"; do
        case "$arg" in
          -c | --config | --config=* | --enable | --disable)
            echo "codex-azure: caller configuration overrides are not allowed" >&2
            exit 2
            ;;
        esac
      done
      exec ${dopplerRun}/bin/doppler-run azure-codex -- codex \
        --disable hooks \
        --disable shell_snapshot \
        -c 'notify=[]' \
        -c 'shell_environment_policy.inherit="core"' \
        -c 'shell_environment_policy.ignore_default_excludes=false' \
        -c 'shell_environment_policy.exclude=["AZURE_OPENAI_API_KEY"]' \
        "$@"
    '';
  };
in
lib.mkMerge [
  {
    home.activation.dopplerLegacyCleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            legacy=${lib.escapeShellArg "${dopplerDir}/env"}
            if [ -e "$legacy" ] || [ -L "$legacy" ]; then
              ${pkgs.python3}/bin/python3 - "$legacy" <<'PY'
      import os, stat, sys
      path = sys.argv[1]
      st = os.lstat(path)
      if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
          raise SystemExit("doppler legacy cleanup: unsafe file type")
      if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o600:
          raise SystemExit("doppler legacy cleanup: unsafe owner or mode")
      PY
              $DRY_RUN_CMD rm -- "$legacy"
            fi
    '';
  }
  (lib.mkIf enableSecrets {
    home.packages = [
      pkgs.doppler
      dopplerRun
      (wrapper "grok-azure" "azure-grok" "grok" "")
      (wrapper "pi-azure" "azure-pi" "pi" "")
      (wrapper "claude-oauth" "claude-oauth" "claude" "")
      codexAzure
    ];
  })
]
