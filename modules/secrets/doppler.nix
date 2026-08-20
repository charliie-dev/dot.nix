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
  # bootstrap 與目標命令共用的隔離 config 目錄:bootstrap 走 --config-dir flag,
  # 目標命令走 DOPPLER_CONFIG_DIR。兩者都不指定的話 doppler 會落回 ~/.doppler
  # 在家目錄建 config;指到 XDG config 又會讓目標命令拿到那裡的 login token。
  dopplerRunConfigDir = "${config.xdg.cacheHome}/doppler-run";
  herdrContextNames = [
    "HERDR_ENV"
    "HERDR_SOCKET_PATH"
    "HERDR_WORKSPACE_ID"
    "HERDR_TAB_ID"
    "HERDR_PANE_ID"
  ];
  unixCoreEnvironmentNames = [
    "PATH"
    "SHELL"
    "TMPDIR"
    "TEMP"
    "TMP"
    "HOME"
    "LANG"
    "LC_ALL"
    "LC_CTYPE"
    "LOGNAME"
    "USER"
  ];
  agentShellEnvironmentNames = unixCoreEnvironmentNames ++ herdrContextNames;
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
      # -I:呼叫者的 PYTHONPATH 可以 shadow 掉 stdlib(放一個 re.py 就行),
      # PYTHONEXECUTABLE 還能換掉下面 re-exec 用的 sys.executable。清理環境
      # 只能決定子行程,這個解譯器本身是在呼叫者的環境下啟動的。
      exec python3 -I ${pkgs.writeText "doppler-run.py" ''
        import os
        import re
        import stat
        import sys
        import tomllib
        from urllib.parse import urlsplit

        TOKEN_PATH = ${builtins.toJSON dopplerTokenPath}
        TOKEN_TARGET = ${builtins.toJSON dopplerTokenTarget}
        RUN_CONFIG_DIR = ${builtins.toJSON dopplerRunConfigDir}
        GROK_CONFIG = ${builtins.toJSON "${config.xdg.configHome}/grok/config.toml"}
        SENSITIVE_NAMES = tuple(${builtins.toJSON sensitiveNames})
        AGENT_SHELL_ENVIRONMENT_NAMES = tuple(${builtins.toJSON agentShellEnvironmentNames})
        SENSITIVE = set(SENSITIVE_NAMES)
        BOOTSTRAP_METADATA = {
            "DOPPLER_PROJECT",
            "DOPPLER_CONFIG",
            "DOPPLER_ENVIRONMENT",
        }
        SANITIZE = SENSITIVE | {"DOPPLER_CONFIG_DIR"}
        # doppler 是 Go 程式,net/http 的 ProxyFromEnvironment 認 *_PROXY,而
        # SSL_CERT_* 會取代系統根憑證 —— 不只在 Linux,Go 1.27 起
        # x509sslcertoverrideplatform 預設 1,darwin 設了這兩個也改從磁碟載入。
        # --api-host 只 pin 住名字,pin 不住路由與信任錨,所以 bootstrap 這段要
        # 另外拿掉。改名暫存再還原,目標命令原封拿回:wrapper 的職責是注入
        # secrets,不是改掉 agent 的網路設定。
        TRANSPORT = (
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "SSL_CERT_FILE", "SSL_CERT_DIR",
        )
        STASH_PREFIX = "__DOPPLER_RUN_STASH_"
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
        GROK_EXCLUDES = SENSITIVE_NAMES
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

        def ensure_run_config_dir():
            validate_private_parents(RUN_CONFIG_DIR)
            try:
                os.makedirs(RUN_CONFIG_DIR, mode=0o700, exist_ok=True)
                st = os.lstat(RUN_CONFIG_DIR)
            except OSError:
                fail("isolated config directory is unavailable")
            if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                fail("isolated config directory has an unsafe type")
            if st.st_uid != os.getuid():
                fail("isolated config directory has an unexpected owner")
            if stat.S_IMODE(st.st_mode) & 0o077:
                os.chmod(RUN_CONFIG_DIR, 0o700)
            reset_run_config_file()

        def reset_run_config_file():
            # 目標命令與 bootstrap 同 uid,可以在離場前把 verify-tls 之類的選項
            # 寫進這個 config file 影響下一次 bootstrap。每次執行前清掉,
            # 讓 bootstrap 的來源只由 flag 與 env token 決定。
            # os.unlink 不跟隨 symlink,刪到的一定是這條路徑本身。
            try:
                os.unlink(os.path.join(RUN_CONFIG_DIR, ".doppler.yaml"))
            except FileNotFoundError:
                return
            except OSError:
                fail("isolated config file cannot be reset")

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
                "inherit", "ignore_default_excludes", "exclude", "include_only"
            }:
                fail("Grok shell environment policy has drifted")
            if (
                policy.get("inherit") != "all"
                or policy.get("ignore_default_excludes") is not False
                or policy.get("exclude") != list(GROK_EXCLUDES)
                or policy.get("include_only") != list(AGENT_SHELL_ENVIRONMENT_NAMES)
            ):
                fail("Grok shell environment policy has drifted")

        def clean_environment(source):
            # 前綴清除而非白名單:doppler 有 40 幾個可經 DOPPLER_* 覆寫的全域選項
            # (api-host、no-verify-tls、dns-resolver 等),逐一列舉遲早漏掉。
            # wrapper 自己要用的值一律在清除後明確設回或改走 CLI flag。
            return {
                k: v
                for k, v in source.items()
                if k not in SANITIZE and not k.startswith("DOPPLER_")
            }

        def bootstrap_environment(source, token):
            env = clean_environment(source)
            stashed = {STASH_PREFIX + n: env.pop(n) for n in TRANSPORT if n in env}
            env.update(stashed)
            env["DOPPLER_TOKEN"] = token
            return env

        def restore_transport(env):
            # 只有 TRANSPORT 裡的名字能被還原;呼叫者自己預埋的其他 stash 名
            # 不會變成真名,連前綴形式也不留給目標命令。
            keep = {n: env[STASH_PREFIX + n] for n in TRANSPORT if STASH_PREFIX + n in env}
            clean = {k: v for k, v in env.items() if not k.startswith(STASH_PREFIX)}
            clean.update(keep)
            return clean

        def bootstrap_argv(profile, command):
            # --no-verify-tls=false 讓 cobra 的 Changed 為真:config file 的
            # verify-tls 是唯一沒有 flag 壓的欄位,只靠 reset 搶跑擋不住同 uid
            # 的背景 writer。加上這個 flag 之後六個 file-scoped 欄位全被 flag
            # 或 env 蓋住(dashboard-host 在 run 路徑上沒人讀),config file 對
            # bootstrap 就沒有影響力了,reset 退回 defence-in-depth。
            # --no-check-version 擋的是版本檢查的網路呼叫;config file 裡那個空
            # 的 version-check 欄位擋不掉,它是 doppler 重建 config 時的固定欄位。
            argv = [
                "${pkgs.doppler}/bin/doppler", "run", "--no-fallback",
                "--no-verify-tls=false", "--no-check-version",
                "--api-host", "https://api.doppler.com",
                "--config-dir", RUN_CONFIG_DIR,
                "--project", "dot-nix", "--config", "dev_personal",
            ]
            for name in PROFILES[profile]:
                argv.extend(("--only-secrets", name))
            # 第二段也要 -I。它是 doppler re-exec 的,環境裡還留著呼叫者的
            # PYTHONPATH,而這個行程已經持有 DOPPLER_TOKEN 與注入的 secret,
            # 頂端 import re 發生在 launch() 的邊界檢查之前。
            argv.extend(("--", sys.executable, "-I", os.path.realpath(__file__),
                         "--internal-launch", profile, "--", *command))
            return argv

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
            final = restore_transport(clean_environment(os.environ))
            if profile == "azure-grok":
                final.pop("GROK_CONFIG", None)
                final.pop("GROK_CONFIG_PATH", None)
                final["GROK_HOME"] = ${builtins.toJSON "${config.xdg.configHome}/grok"}
            if profile == "azure-codex":
                final["CODEX_HOME"] = ${builtins.toJSON "${config.xdg.configHome}/codex"}
            final["DOPPLER_CONFIG_DIR"] = RUN_CONFIG_DIR
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
            ensure_run_config_dir()
            # 來源固定全部走 flag:doppler 的優先序是 flag > env > config file。
            env = bootstrap_environment(os.environ, token)
            argv = bootstrap_argv(profile, command)
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
          -c | -c?* | --config | --config=* | -p | -p?* | --profile | --profile=* | --enable | --enable=* | --disable | --disable=*)
            echo "codex-azure: caller configuration overrides are not allowed" >&2
            exit 2
            ;;
        esac
      done
      herdr_context_names=(
        HERDR_ENV
        HERDR_SOCKET_PATH
        HERDR_WORKSPACE_ID
        HERDR_TAB_ID
        HERDR_PANE_ID
      )
      herdr_present=0
      for name in "''${herdr_context_names[@]}"; do
        if [[ -v $name ]]; then
          ((herdr_present += 1))
        fi
      done
      if ((herdr_present != 0 && herdr_present != 5)); then
        echo "codex-azure: partial Herdr context is not allowed" >&2
        exit 2
      fi
      trusted_herdr_args=()
      for name in "''${herdr_context_names[@]}"; do
        if ((herdr_present == 5)); then
          value="''${!name}"
        else
          value=""
        fi
        json="$(printf '%s' "$value" | ${lib.getExe pkgs.jq} -Rs .)"
        trusted_herdr_args+=( -c "shell_environment_policy.set.$name=$json" )
      done
      exec ${dopplerRun}/bin/doppler-run azure-codex -- codex \
        --disable hooks \
        --disable shell_snapshot \
        -c 'notify=[]' \
        -c 'shell_environment_policy.inherit="all"' \
        -c 'shell_environment_policy.include_only=${builtins.toJSON agentShellEnvironmentNames}' \
        -c 'shell_environment_policy.ignore_default_excludes=false' \
        -c 'shell_environment_policy.exclude=["AZURE_OPENAI_API_KEY"]' \
        "''${trusted_herdr_args[@]}" \
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
