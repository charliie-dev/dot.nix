{
  config,
  pkgs,
  lib,
  ...
}:
let
  isLinux = pkgs.stdenv.isLinux;
  dockerConfigDir = "${config.xdg.configHome}/docker";
  dockerConfigFile = "${dockerConfigDir}/config.json";
  dockerLockFile = "${config.xdg.configHome}/.docker-config.lock";
  passwordStoreDir = "${config.xdg.dataHome}/password-store";
  gpgHome = "${config.xdg.dataHome}/gnupg";
  credentialsStore = if isLinux then "pass" else "osxkeychain";
  garRegistries = [ "asia-east1-docker.pkg.dev" ];
  credentialPackages = [
    pkgs.docker-credential-gcr
    pkgs.docker-credential-helpers
  ]
  ++ lib.optionals isLinux [ pkgs.pass ];
  bootstrapProgram = pkgs.writeShellApplication {
    name = "home-manager-docker-credentials";
    runtimeInputs = [
      pkgs.python3
      pkgs.jq
    ]
    ++ lib.optionals isLinux [
      pkgs.gnupg
      pkgs.pass
    ];
    text = ''
      exec python3 ${pkgs.writeText "home-manager-docker-credentials.py" ''
        import argparse
        import fcntl
        import hashlib
        import json
        import os
        import stat
        import subprocess
        import tempfile
        import time

        UID = "Home Manager Docker Credentials <docker-credentials@localhost>"
        BOOTSTRAP_MARKER_NAME = ".home-manager-docker-bootstrap-in-progress"
        BOOTSTRAP_MARKER_CONTENT = b"bootstrap-in-progress\n"
        GAR_REGISTRIES = ${builtins.toJSON garRegistries}

        def fail(message):
            raise SystemExit("docker credentials: " + message)

        def exists(path):
            try:
                os.lstat(path)
                return True
            except FileNotFoundError:
                return False

        def beneath(path, root):
            absolute = os.path.abspath(path)
            base = os.path.abspath(root)
            if os.path.commonpath((absolute, base)) != base:
                fail("managed path escapes its expected root")
            return absolute

        def validate_directory(path, exact_mode=None):
            try:
                st = os.lstat(path)
            except OSError:
                fail("required directory is unavailable")
            if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                fail("managed directory has an unsafe type")
            if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o022:
                fail("managed directory has unsafe ownership or mode")
            if exact_mode is not None and stat.S_IMODE(st.st_mode) != exact_mode:
                fail("managed directory mode must be 0700")
            return st

        def validate_existing_parents(path, root):
            target = beneath(path, root)
            current = os.path.abspath(root)
            validate_directory(current)
            relative = os.path.relpath(os.path.dirname(target), current)
            for component in (() if relative == "." else relative.split(os.sep)):
                current = os.path.join(current, component)
                validate_directory(current)

        def ensure_leaf_directory(path, root):
            validate_existing_parents(path, root)
            if not exists(path):
                os.mkdir(path, 0o700)
            validate_directory(path, 0o700)

        def open_regular(path, modes, missing_ok=False, writable=False):
            flags = os.O_RDWR if writable else os.O_RDONLY
            flags |= getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(path, flags)
            except FileNotFoundError:
                if missing_ok:
                    return None
                fail("required file is missing")
            except OSError:
                fail("managed file cannot be opened safely")
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1:
                os.close(fd)
                fail("managed file has unsafe type, owner, or link count")
            if stat.S_IMODE(st.st_mode) not in modes:
                os.close(fd)
                fail("managed file has unsafe mode")
            return fd

        def read_fd(fd):
            os.lseek(fd, 0, os.SEEK_SET)
            chunks = []
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    return b"".join(chunks)
                chunks.append(chunk)

        def identity(fd, content):
            st = os.fstat(fd)
            return (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns,
                    st.st_ctime_ns, hashlib.sha256(content).digest())

        def inspect_config(path):
            fd = open_regular(path, {0o600}, missing_ok=True)
            if fd is None:
                return None, b"{}\n", None
            content = read_fd(fd)
            source_identity = identity(fd, content)
            os.close(fd)
            try:
                document = json.loads(content)
            except (UnicodeDecodeError, json.JSONDecodeError):
                fail("Docker config is not valid JSON")
            if not isinstance(document, dict):
                fail("Docker config must be a JSON object")
            store = document.get("credsStore")
            helpers = document.get("credHelpers")
            auths = document.get("auths", {})
            if store is not None and not isinstance(store, str):
                fail("Docker credsStore has an invalid type")
            if helpers is not None and (
                not isinstance(helpers, dict)
                or any(not isinstance(key, str) or not isinstance(value, str)
                       for key, value in helpers.items())
            ):
                fail("Docker credHelpers has an invalid type")
            if not isinstance(auths, dict):
                fail("Docker auths has an invalid type")

            def credential_fields(value):
                if isinstance(value, dict):
                    for key, child in value.items():
                        if not isinstance(key, str):
                            fail("Docker auths contains a non-string field")
                        folded = key.casefold()
                        if (folded == "auth" or folded.endswith("token")) and child not in (None, ""):
                            return True
                        if credential_fields(child):
                            return True
                elif isinstance(value, list):
                    return any(credential_fields(child) for child in value)
                return False

            if any(not isinstance(value, dict) for value in auths.values()):
                fail("Docker auth registry entries must be objects")
            if any(credential_fields(value) for value in auths.values()):
                fail("inline Docker auth/token credentials are not allowed")
            if store not in (None, "", args.store):
                fail("Docker config has a conflicting credsStore")
            for registry in GAR_REGISTRIES:
                if helpers is not None and helpers.get(registry, "gcr") != "gcr":
                    fail("Docker config has a conflicting GAR credential helper")
            return document, content, source_identity

        def validate_nested_store(root):
            encrypted = False
            for current, directories, files in os.walk(root, topdown=True, followlinks=False):
                validate_directory(current)
                for name in directories + files:
                    path = os.path.join(current, name)
                    st = os.lstat(path)
                    if stat.S_ISLNK(st.st_mode):
                        fail("password store contains a symlink")
                    if st.st_uid != os.getuid():
                        fail("password store entry has an unexpected owner")
                    if stat.S_ISDIR(st.st_mode):
                        if stat.S_IMODE(st.st_mode) & 0o022:
                            fail("password store directory has unsafe mode")
                        continue
                    if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
                        fail("password store contains an unsafe entry")
                    if stat.S_IMODE(st.st_mode) & 0o022:
                        fail("password store file has unsafe mode")
                    if name.endswith(".gpg"):
                        encrypted = True
            return encrypted

        def run_gpg(arguments, input_data=None, check=True):
            result = subprocess.run(
                ["gpg", "--batch", "--no-tty", *arguments],
                input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False,
            )
            if check and result.returncode != 0:
                operation = next((item.lstrip("-") for item in arguments
                                  if item in {"--quick-generate-key", "--quick-add-key",
                                              "--encrypt", "--decrypt"}), "operation")
                fail("GPG " + operation + " failed")
            return result

        def colon_records(secret=False):
            command = ["--with-colons", "--fixed-list-mode", "--with-fingerprint"]
            command.append("--list-secret-keys" if secret else "--list-keys")
            result = run_gpg(command, check=False)
            if result.returncode not in (0, 2):
                fail("GPG key inspection failed")
            records = []
            for raw in result.stdout.decode("utf-8", "strict").splitlines():
                fields = raw.split(":")
                fields.extend([""] * (18 - len(fields)))
                records.append(fields)
            return records

        def key_groups(records, primary_type):
            groups = []
            current = None
            pending = None
            for fields in records:
                kind = fields[0]
                if kind == primary_type:
                    current = {"primary": fields, "primary_fpr": None, "uids": [], "subs": []}
                    groups.append(current)
                    pending = (current, "primary_fpr")
                elif current is not None and kind == "uid":
                    current["uids"].append(fields[9])
                elif current is not None and kind in ("sub", "ssb"):
                    entry = {"record": fields, "fpr": None}
                    current["subs"].append(entry)
                    pending = (entry, "fpr")
                elif current is not None and kind == "fpr" and pending is not None:
                    pending[0][pending[1]] = fields[9]
                    pending = None
            return groups

        def valid_record(fields, algorithm, curve, capabilities):
            validity = fields[1]
            expiry = fields[6]
            actual_caps = {char for char in fields[11] if char in "cesa"}
            return (
                validity not in {"r", "e", "d", "i"}
                and expiry in {"", "0"}
                and fields[3] == algorithm
                and fields[16] == curve
                and actual_caps == capabilities
            )

        def exact_key_structure():
            public_matches = [
                group for group in key_groups(colon_records(), "pub") if UID in group["uids"]
            ]
            if not public_matches:
                return None
            if len(public_matches) != 1:
                fail("dedicated Docker GPG identity is ambiguous")
            key = public_matches[0]
            if (
                key["uids"] != [UID]
                or not key["primary_fpr"]
                or not valid_record(key["primary"], "22", "ed25519", {"c"})
                or len(key["subs"]) != 1
                or not key["subs"][0]["fpr"]
                or not valid_record(key["subs"][0]["record"], "18", "cv25519", {"e"})
            ):
                fail("dedicated Docker GPG identity has an invalid structure")
            secret_matches = [
                group for group in key_groups(colon_records(True), "sec")
                if UID in group["uids"]
            ]
            if len(secret_matches) != 1:
                fail("dedicated Docker GPG secret state is incomplete")
            secret = secret_matches[0]
            if (
                secret["uids"] != [UID]
                or secret["primary_fpr"] != key["primary_fpr"]
                or not valid_record(secret["primary"], "22", "ed25519", {"c"})
                or len(secret["subs"]) != 1
            ):
                fail("dedicated Docker GPG secret primary does not match exactly")
            encryption_fingerprints = [
                entry["fpr"] for entry in secret["subs"]
                if entry["fpr"] == key["subs"][0]["fpr"]
                and valid_record(entry["record"], "18", "cv25519", {"e"})
            ]
            if len(encryption_fingerprints) != 1:
                fail("expected exactly one usable secret encryption fingerprint")
            return key["primary_fpr"], encryption_fingerprints[0]

        def marker_identity(fd):
            st = os.fstat(fd)
            return st.st_dev, st.st_ino

        def validate_bootstrap_marker(path):
            fd = open_regular(path, {0o600})
            try:
                if read_fd(fd) != BOOTSTRAP_MARKER_CONTENT:
                    fail("Docker GPG bootstrap marker has unexpected content")
                return marker_identity(fd)
            finally:
                os.close(fd)

        def fsync_directory(path):
            directory_fd = os.open(path, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)

        def create_bootstrap_marker(path):
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(path, flags, 0o600)
            except FileExistsError:
                validate_bootstrap_marker(path)
                fail("an interrupted Docker GPG bootstrap requires deliberate remediation")
            except OSError:
                fail("Docker GPG bootstrap marker cannot be created safely")
            try:
                st = os.fstat(fd)
                if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1:
                    fail("Docker GPG bootstrap marker has unsafe metadata")
                os.fchmod(fd, 0o600)
                os.write(fd, BOOTSTRAP_MARKER_CONTENT)
                os.fsync(fd)
                created_identity = marker_identity(fd)
            finally:
                os.close(fd)
            fsync_directory(os.path.dirname(path))
            return created_identity

        def remove_bootstrap_marker(path, created_identity):
            if args.test_delay_before_marker_remove:
                time.sleep(0.25)
            current_identity = validate_bootstrap_marker(path)
            if current_identity != created_identity:
                fail("Docker GPG bootstrap marker changed before removal")
            path_st = os.lstat(path)
            if (path_st.st_dev, path_st.st_ino) != created_identity:
                fail("Docker GPG bootstrap marker changed before removal")
            os.unlink(path)
            fsync_directory(os.path.dirname(path))

        def checkpoint(name):
            if args.test_fail_at == name:
                fail("injected fixture failure")

        def generate_key():
            command = [
                "--pinentry-mode", "loopback", "--passphrase", "",
                "--quick-generate-key", UID, "ed25519", "cert", "0",
            ]
            run_gpg(command)
            checkpoint("after-primary")
            partial = [
                group for group in key_groups(colon_records(), "pub") if UID in group["uids"]
            ]
            if len(partial) != 1 or not partial[0]["primary_fpr"]:
                fail("generated GPG primary cannot be identified")
            run_gpg([
                "--pinentry-mode", "loopback", "--passphrase", "",
                "--quick-add-key", partial[0]["primary_fpr"], "cv25519", "encr", "0",
            ])
            checkpoint("after-subkey")

        def verify_passwordless(encryption_fingerprint):
            payload = b"home-manager-docker-credential-fixture\n"
            encrypted = run_gpg([
                "--trust-model", "always", "--encrypt", "--recipient",
                encryption_fingerprint + "!",
            ], payload).stdout
            decrypted = run_gpg([
                "--pinentry-mode", "loopback", "--passphrase", "", "--decrypt",
            ], encrypted).stdout
            if decrypted != payload:
                fail("dedicated Docker GPG key failed passwordless verification")

        def read_recipient(path):
            fd = open_regular(path, {0o600})
            content = read_fd(fd)
            os.close(fd)
            try:
                logical = [line.strip() for line in content.decode("utf-8").splitlines()
                           if line.strip() and not line.lstrip().startswith("#")]
            except UnicodeDecodeError:
                fail("password store recipient is not UTF-8")
            if len(logical) != 1:
                fail("password store must have exactly one logical recipient")
            return logical[0]

        def ensure_password_store():
            ensure_leaf_directory(args.gnupg_home, args.xdg_data)
            ensure_leaf_directory(args.password_store, args.xdg_data)
            marker = os.path.join(args.gnupg_home, BOOTSTRAP_MARKER_NAME)
            if exists(marker):
                validate_bootstrap_marker(marker)
                fail("an interrupted Docker GPG bootstrap requires deliberate remediation")
            encrypted_entries = validate_nested_store(args.password_store)
            gpg_id = os.path.join(args.password_store, ".gpg-id")
            if exists(gpg_id):
                recipient = read_recipient(gpg_id)
                structure = exact_key_structure()
                if structure is None or recipient not in structure:
                    fail("password store recipient does not resolve to the dedicated usable key")
                verify_passwordless(structure[1])
                return
            if encrypted_entries:
                fail("password store has encrypted entries without .gpg-id")
            structure = exact_key_structure()
            created_marker_identity = None
            if structure is None:
                created_marker_identity = create_bootstrap_marker(marker)
                generate_key()
                structure = exact_key_structure()
            checkpoint("after-verification")
            verify_passwordless(structure[1])
            subprocess_result = subprocess.run(
                ["pass", "init", structure[1]], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, check=False,
            )
            if subprocess_result.returncode != 0:
                fail("pass init failed")
            checkpoint("after-pass-init")
            if not exists(gpg_id):
                fail("pass init did not create .gpg-id")
            recipient = read_recipient(gpg_id)
            verified = exact_key_structure()
            if verified is None or recipient not in verified:
                fail("pass init recipient does not resolve exactly")
            if created_marker_identity is not None:
                remove_bootstrap_marker(marker, created_marker_identity)

        def unchanged(path, expected_identity, expected_content):
            if expected_identity is None:
                return not exists(path)
            fd = open_regular(path, {0o600})
            content = read_fd(fd)
            current = identity(fd, content)
            os.close(fd)
            return current == expected_identity and content == expected_content

        def replace_config(path, document, expected_identity, expected_content):
            document["credsStore"] = args.store
            helpers = document.get("credHelpers") or {}
            for registry in GAR_REGISTRIES:
                helpers[registry] = "gcr"
            document["credHelpers"] = helpers
            rendered = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode()
            fd, temporary = tempfile.mkstemp(prefix=".config.json.", dir=os.path.dirname(path))
            try:
                os.fchmod(fd, 0o600)
                os.write(fd, rendered)
                os.fsync(fd)
                os.close(fd)
                fd = -1
                checkpoint("before-replace")
                if args.test_delay_before_replace:
                    time.sleep(0.25)
                if not unchanged(path, expected_identity, expected_content):
                    fail("Docker config changed before replacement")
                os.replace(temporary, path)
                temporary = None
                directory_fd = os.open(os.path.dirname(path), os.O_RDONLY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            finally:
                if fd >= 0:
                    os.close(fd)
                if temporary is not None:
                    try:
                        os.unlink(temporary)
                    except FileNotFoundError:
                        pass

        def parse_args():
            parser = argparse.ArgumentParser()
            parser.add_argument("--home", required=True)
            parser.add_argument("--xdg-config", required=True)
            parser.add_argument("--xdg-data", required=True)
            parser.add_argument("--docker-config", required=True)
            parser.add_argument("--lock", required=True)
            parser.add_argument("--gnupg-home", required=True)
            parser.add_argument("--password-store", required=True)
            parser.add_argument("--store", required=True)
            parser.add_argument("--linux", action="store_true")
            parser.add_argument("--dry-run", action="store_true")
            parser.add_argument("--test-fail-at", choices=(
                "after-primary", "after-subkey", "after-verification",
                "after-pass-init", "before-replace",
            ))
            parser.add_argument("--test-delay-before-replace", action="store_true")
            parser.add_argument("--test-delay-before-marker-remove", action="store_true")
            return parser.parse_args()

        args = parse_args()
        if args.dry_run:
            raise SystemExit(0)
        os.umask(0o077)
        args.home = os.path.abspath(args.home)
        args.xdg_config = beneath(args.xdg_config, args.home)
        args.xdg_data = beneath(args.xdg_data, args.home)
        validate_directory(args.home)
        validate_existing_parents(os.path.join(args.xdg_config, ".boundary"), args.home)
        validate_existing_parents(os.path.join(args.xdg_data, ".boundary"), args.home)
        validate_directory(args.xdg_config)
        validate_directory(args.xdg_data)
        args.docker_config = beneath(args.docker_config, args.xdg_config)
        args.lock = beneath(args.lock, args.xdg_config)
        args.gnupg_home = beneath(args.gnupg_home, args.xdg_data)
        args.password_store = beneath(args.password_store, args.xdg_data)
        docker_directory = os.path.dirname(args.docker_config)
        ensure_leaf_directory(docker_directory, args.xdg_config)
        validate_existing_parents(args.lock, args.home)
        if not exists(args.lock):
            flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            try:
                lock_fd = os.open(args.lock, flags, 0o600)
            except FileExistsError:
                lock_fd = open_regular(args.lock, {0o600}, writable=True)
        else:
            lock_fd = open_regular(args.lock, {0o600}, writable=True)
        lock_st = os.fstat(lock_fd)
        if not stat.S_ISREG(lock_st.st_mode) or lock_st.st_uid != os.getuid() or lock_st.st_nlink != 1:
            os.close(lock_fd)
            fail("Docker credential lock has unsafe metadata")
        os.fchmod(lock_fd, 0o600)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            document, content, source_identity = inspect_config(args.docker_config)
            if document is None:
                document = {}
            if args.linux:
                os.environ["GNUPGHOME"] = args.gnupg_home
                os.environ["PASSWORD_STORE_DIR"] = args.password_store
                ensure_password_store()
            replace_config(args.docker_config, document, source_identity, content)
        finally:
            os.close(lock_fd)
      ''} "$@"
    '';
  };
in
{
  home = {
    packages = credentialPackages ++ [ bootstrapProgram ];
    sessionVariables = lib.mkIf isLinux {
      PASSWORD_STORE_DIR = passwordStoreDir;
    };

    activation.dockerCredentials = lib.hm.dag.entryAfter [ "authorizedKeys" ] ''
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        ${bootstrapProgram}/bin/home-manager-docker-credentials \
          --home ${lib.escapeShellArg config.home.homeDirectory} \
          --xdg-config ${lib.escapeShellArg config.xdg.configHome} \
          --xdg-data ${lib.escapeShellArg config.xdg.dataHome} \
          --docker-config ${lib.escapeShellArg dockerConfigFile} \
          --lock ${lib.escapeShellArg dockerLockFile} \
          --gnupg-home ${lib.escapeShellArg gpgHome} \
          --password-store ${lib.escapeShellArg passwordStoreDir} \
          --store ${lib.escapeShellArg credentialsStore} \
          ${lib.optionalString isLinux "--linux"}
      fi
    '';
  };
}
