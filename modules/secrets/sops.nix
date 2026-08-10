{
  config,
  pkgs,
  lib,
  src,
  enableSecrets ? false,
  enableSshSecrets ? enableSecrets,
  ...
}:
let
  sopsEnabled = enableSecrets || enableSshSecrets;
  pinnedFingerprint = "SHA256:DdWGvlMmBCptRDumMUS7sUjoD/W0BCOhLTQnF5Iw+m8";
  sshDir = "${config.home.homeDirectory}/.ssh";
  authorizedKeys = "${sshDir}/authorized_keys";
  publicKey = "${sshDir}/id_ed25519.pub";
  publicKeyTarget = "${config.xdg.configHome}/sops-nix/secrets/ssh_ed25519_pub";
  authorizedKeysManager = pkgs.writeShellApplication {
    name = "manage-authorized-keys";
    runtimeInputs = [
      pkgs.openssh
      pkgs.python3
    ];
    text = ''
      exec python3 ${pkgs.writeText "manage-authorized-keys.py" ''
        import argparse
        import fcntl
        import os
        import pwd
        import re
        import stat
        import subprocess

        PIN = ${builtins.toJSON pinnedFingerprint}
        PUBLIC_KEY_TARGET = ${builtins.toJSON publicKeyTarget}
        HOME_DIR = ${builtins.toJSON config.home.homeDirectory}
        SSH_KEYGEN = ${builtins.toJSON "${pkgs.openssh}/bin/ssh-keygen"}
        FINGERPRINT_RE = re.compile(r"^SHA256:[0-9A-Za-z+/]+={0,2}$")
        RECORD_RE = re.compile(
            rb"^[ \t]*ssh-ed25519[ \t]+([^ \t]+)(?:[ \t]+[\t -~]*)?$"
        )
        MAX_RECORD_BYTES = 4096
        TARGET_MODES = {0o600, 0o644}
        TEST_HOOK = lambda event: None

        class ShortWrite(Exception):
            def __init__(self, written):
                super().__init__("short append")
                self.written = written

        def fail(message):
            raise SystemExit("authorized_keys: " + message)

        def require_primitives():
            required = ("O_NOFOLLOW", "O_DIRECTORY", "O_APPEND")
            if any(not getattr(os, name, 0) for name in required):
                fail("required safe filesystem primitives are unavailable")
            if not hasattr(fcntl, "flock"):
                fail("required file locking primitive is unavailable")

        def validate_regular(st, modes, label):
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                fail(label + " has an unsafe type or owner")
            if st.st_nlink != 1 or stat.S_IMODE(st.st_mode) not in modes:
                fail(label + " has an unsafe link count or mode")

        def validate_home_component(st, final):
            if not stat.S_ISDIR(st.st_mode) or stat.S_IMODE(st.st_mode) & 0o022:
                fail("home path has an unsafe type or mode")
            if final and st.st_uid != os.getuid():
                fail("home directory has an unsafe owner")

        def fingerprint_record(record):
            if not record:
                return None
            try:
                result = subprocess.run(
                    [SSH_KEYGEN, "-E", "sha256", "-lf", "-"],
                    input=record + b"\n",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            except OSError:
                fail("ssh-keygen is unavailable")
            if result.returncode != 0:
                return None
            try:
                output = result.stdout.decode("ascii").splitlines()
            except UnicodeDecodeError:
                return None
            if len(output) != 1:
                return None
            fields = output[0].split(maxsplit=2)
            if len(fields) < 2 or not FINGERPRINT_RE.fullmatch(fields[1]):
                return None
            return fields[1]

        def valid_content_bytes(content):
            if not content or len(content) > MAX_RECORD_BYTES:
                return False
            return not any(byte < 0x20 and byte != 0x09 or byte == 0x7f for byte in content)

        def parse_unrestricted(content, canonical_blob):
            if not valid_content_bytes(content):
                return False
            match = RECORD_RE.fullmatch(content)
            if match is None or match.group(1) != canonical_blob:
                return False
            return fingerprint_record(content) == PIN

        def validate_canonical_bytes(data):
            if data.endswith(b"\r\n"):
                content = data[:-2]
            elif data.endswith(b"\n"):
                content = data[:-1]
            else:
                content = data
            if b"\r" in content or b"\n" in content or not valid_content_bytes(content):
                fail("decrypted public key has invalid record bytes")
            match = RECORD_RE.fullmatch(content)
            if match is None or not content.lstrip(b" \t").startswith(b"ssh-ed25519"):
                fail("decrypted public key is not an unrestricted ssh-ed25519 record")
            if fingerprint_record(content) != PIN:
                fail("decrypted public key does not match the pinned fingerprint")
            return content, match.group(1)

        def available_bytes(data, canonical_blob):
            records = data.split(b"\n")
            last = len(records) - 1
            for index, raw in enumerate(records):
                terminated = index < last
                content = raw[:-1] if terminated and raw.endswith(b"\r") else raw
                if parse_unrestricted(content, canonical_blob):
                    return True
            return False

        def append_payload(last_byte, canonical):
            separator = b"" if not last_byte or last_byte == b"\n" else b"\n"
            return separator + canonical + b"\n"

        def write_once(fd, payload, writer=os.write):
            while True:
                try:
                    written = writer(fd, payload)
                    break
                except InterruptedError:
                    continue
            if written != len(payload):
                raise ShortWrite(written)
            return written

        def read_regular_path(path, modes):
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            except OSError:
                fail("required key file cannot be opened safely")
            try:
                st = os.fstat(fd)
                validate_regular(st, modes, "required key file")
                chunks = []
                while True:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                return b"".join(chunks)
            finally:
                os.close(fd)

        def read_expected_link(path, expected_target, allowed_modes):
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
            return read_regular_path(expected_target, allowed_modes)

        def entry_stat(directory_fd, name, missing_ok=False):
            try:
                return os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                if missing_ok:
                    return None
                fail("managed file is missing")
            except OSError:
                fail("managed file cannot be inspected safely")

        def same_entry(directory_fd, name, st):
            current = entry_stat(directory_fd, name, True)
            return current is not None and (current.st_dev, current.st_ino) == (st.st_dev, st.st_ino)

        def open_home_ssh(target):
            expected = os.path.join(HOME_DIR, ".ssh", "authorized_keys")
            if os.path.normpath(target) != expected or os.environ.get("HOME") != HOME_DIR:
                fail("managed path is outside the authoritative home")
            try:
                authoritative = pwd.getpwuid(os.getuid()).pw_dir
            except KeyError:
                fail("current user has no authoritative home")
            if authoritative != HOME_DIR:
                fail("configured and authoritative homes differ")

            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            directory_fd = os.open("/", flags)
            try:
                parts = [part for part in HOME_DIR.split("/") if part]
                for index, part in enumerate(parts):
                    next_fd = os.open(part, flags, dir_fd=directory_fd)
                    os.close(directory_fd)
                    directory_fd = next_fd
                    st = os.fstat(directory_fd)
                    validate_home_component(st, index == len(parts) - 1)
                ssh_fd = os.open(".ssh", flags, dir_fd=directory_fd)
            except OSError:
                os.close(directory_fd)
                fail("home path cannot be opened without following links")
            os.close(directory_fd)
            ssh_st = os.fstat(ssh_fd)
            if ssh_st.st_uid != os.getuid() or stat.S_IMODE(ssh_st.st_mode) != 0o700:
                os.close(ssh_fd)
                fail("SSH directory has unsafe ownership or mode")
            return ssh_fd

        def scan_fd(fd, canonical_blob):
            os.lseek(fd, 0, os.SEEK_SET)
            available = False
            record = bytearray()
            oversized = False
            last_byte = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                last_byte = chunk[-1:]
                for byte in chunk:
                    if byte == 0x0a:
                        content = bytes(record[:-1] if record.endswith(b"\r") else record)
                        if not oversized and parse_unrestricted(content, canonical_blob):
                            available = True
                        record.clear()
                        oversized = False
                    elif not oversized:
                        record.append(byte)
                        if len(record) > MAX_RECORD_BYTES + 1:
                            record.clear()
                            oversized = True
            if record and not oversized and parse_unrestricted(bytes(record), canonical_blob):
                available = True
            return available, last_byte

        def open_read_entry(ssh_fd, name, canonical_blob, missing_ok):
            before = entry_stat(ssh_fd, name, missing_ok)
            if before is None:
                return None
            try:
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=ssh_fd)
            except OSError:
                fail("authorized_keys cannot be opened safely")
            try:
                opened = os.fstat(fd)
                validate_regular(opened, TARGET_MODES, "authorized_keys")
                if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                    fail("authorized_keys changed during safe open")
                available, last_byte = scan_fd(fd, canonical_blob)
                after = os.fstat(fd)
                validate_regular(after, TARGET_MODES, "authorized_keys")
                if not same_entry(ssh_fd, name, after):
                    fail("authorized_keys changed during safe read")
                return available, last_byte
            finally:
                os.close(fd)

        def open_lock(ssh_fd, name):
            flags = os.O_RDWR | os.O_NOFOLLOW
            try:
                fd = os.open(name, flags | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=ssh_fd)
            except FileExistsError:
                try:
                    fd = os.open(name, flags, dir_fd=ssh_fd)
                except OSError:
                    fail("lock file cannot be opened safely")
            except OSError:
                fail("lock file cannot be created safely")
            st = os.fstat(fd)
            validate_regular(st, {0o600}, "lock file")
            if not same_entry(ssh_fd, name, st):
                os.close(fd)
                fail("lock file changed during safe open")
            fcntl.flock(fd, fcntl.LOCK_EX)
            st = os.fstat(fd)
            validate_regular(st, {0o600}, "lock file")
            if not same_entry(ssh_fd, name, st):
                os.close(fd)
                fail("lock file changed while locking")
            return fd

        def open_append_target(ssh_fd, name):
            flags = os.O_RDWR | os.O_APPEND | os.O_NOFOLLOW
            created = False
            try:
                fd = os.open(name, flags, dir_fd=ssh_fd)
            except FileNotFoundError:
                try:
                    fd = os.open(name, flags | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=ssh_fd)
                    created = True
                except FileExistsError:
                    try:
                        fd = os.open(name, flags, dir_fd=ssh_fd)
                    except OSError:
                        fail("authorized_keys changed during creation")
                except OSError:
                    fail("authorized_keys cannot be created safely")
            except OSError:
                fail("authorized_keys cannot be opened safely")
            st = os.fstat(fd)
            validate_regular(st, TARGET_MODES, "authorized_keys")
            if not same_entry(ssh_fd, name, st):
                os.close(fd)
                fail("authorized_keys changed during append open")
            return fd, created

        def sync_created_directory(ssh_fd):
            try:
                os.fsync(ssh_fd)
            except OSError:
                fail("SSH directory cannot be synchronized")

        def manage_authorized(target, canonical_data, dry_run):
            require_primitives()
            canonical, canonical_blob = validate_canonical_bytes(canonical_data)
            ssh_fd = open_home_ssh(target)
            name = "authorized_keys"
            try:
                observed = open_read_entry(ssh_fd, name, canonical_blob, True)
                if observed is not None and observed[0]:
                    return "no-op"
                if dry_run:
                    return "would append"

                lock_fd = open_lock(ssh_fd, name + ".lock")
                try:
                    target_fd, created = open_append_target(ssh_fd, name)
                    try:
                        target_st = os.fstat(target_fd)
                        available, last_byte = scan_fd(target_fd, canonical_blob)
                        TEST_HOOK("before-write")
                        if not same_entry(ssh_fd, name, target_st):
                            fail("authorized_keys changed before append")
                        if available:
                            return "no-op"
                        payload = append_payload(last_byte, canonical)
                        try:
                            write_once(target_fd, payload)
                        except ShortWrite:
                            os.fsync(target_fd)
                            if created:
                                sync_created_directory(ssh_fd)
                            fail("append was incomplete")
                        except OSError:
                            if created:
                                sync_created_directory(ssh_fd)
                            fail("append failed")
                        os.fsync(target_fd)
                        if created:
                            sync_created_directory(ssh_fd)
                    finally:
                        os.close(target_fd)
                    TEST_HOOK("before-final-read")
                    final = open_read_entry(ssh_fd, name, canonical_blob, False)
                    if not final[0]:
                        fail("final safe read did not observe the pinned key")
                    TEST_HOOK("after-final-read")
                    return "appended"
                finally:
                    os.close(lock_fd)
            finally:
                os.close(ssh_fd)

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--enabled", action="store_true")
            parser.add_argument("--dry-run", action="store_true")
            parser.add_argument("--authorized", required=True)
            parser.add_argument("--public-key")
            args = parser.parse_args()
            if not args.enabled:
                return
            require_primitives()
            public = read_expected_link(args.public_key, PUBLIC_KEY_TARGET, {0o644})
            canonical, _ = validate_canonical_bytes(public)
            result = manage_authorized(args.authorized, canonical, args.dry_run)
            if args.dry_run:
                print(result)

        if __name__ == "__main__":
            main()
      ''} "$@"
    '';
  };
  activationArgs = lib.optionalString enableSshSecrets "--enabled --public-key ${lib.escapeShellArg publicKey}";
  sopsSyncLocked = pkgs.writeShellApplication {
    name = "sops-nix-sync-locked";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
            exec python3 - ${lib.escapeShellArg "${config.xdg.cacheHome}/sops-nix/decrypt.lock"} "$@" <<'PY'
      import fcntl
      import os
      import stat
      import sys

      lock_path, *command = sys.argv[1:]
      if not command:
          raise SystemExit("sops-nix-sync-locked: missing command")
      parent = os.path.dirname(lock_path)
      os.makedirs(parent, mode=0o700, exist_ok=True)
      st = os.lstat(parent)
      if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
          raise SystemExit("sops-nix lock directory has an unsafe type")
      if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
          raise SystemExit("sops-nix lock directory has unsafe ownership or mode")
      fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
      try:
          fst = os.fstat(fd)
          if not stat.S_ISREG(fst.st_mode) or fst.st_uid != os.getuid():
              raise SystemExit("sops-nix lock file has an unsafe type or owner")
          os.fchmod(fd, 0o600)
          os.set_inheritable(fd, True)
          fcntl.flock(fd, fcntl.LOCK_EX)
          os.execvp(command[0], command)
      finally:
          os.close(fd)
      PY
    '';
  };
in
lib.mkMerge [
  {
    home.packages = [ authorizedKeysManager ];
    home.activation.sops-nix-sync =
      if sopsEnabled then
        lib.hm.dag.entryAfter
          [
            (if pkgs.stdenv.isDarwin then "setupLaunchAgents" else "reloadSystemd")
          ]
          (
            if pkgs.stdenv.isDarwin then
              ''
                $DRY_RUN_CMD ${config.launchd.agents.sops-nix-sync.config.Program}
              ''
            else
              ''
                $DRY_RUN_CMD ${sopsSyncLocked}/bin/sops-nix-sync-locked \
                  ${config.systemd.user.systemctlPath} restart --user sops-nix
              ''
          )
      else
        lib.hm.dag.entryAfter [ "writeBoundary" ] "";
    home.activation.authorizedKeys = lib.hm.dag.entryAfter [ "sops-nix-sync" ] ''
      $DRY_RUN_CMD ${authorizedKeysManager}/bin/manage-authorized-keys \
        ${activationArgs} \
        --authorized ${lib.escapeShellArg authorizedKeys}
    '';
  }
  (lib.mkIf sopsEnabled {
    sops = {
      defaultSopsFile = "${src}/conf.d/sops/secrets.yaml";
      age.keyFile = "${config.xdg.configHome}/age/keys.txt";
    };

    systemd.user.services.sops-nix.Service = lib.mkIf pkgs.stdenv.isLinux {
      Type = lib.mkForce "oneshot";
    };

    # The explicit synchronous node above owns decryption ordering.
    home.activation.sops-nix = lib.mkForce (lib.hm.dag.entryAfter [ "writeBoundary" ] "");
  })
  (lib.mkIf enableSshSecrets {
    sops.secrets = {
      ssh_ed25519 = {
        path = "${sshDir}/id_ed25519";
        mode = "0600";
      };
      ssh_ed25519_pub = {
        path = publicKey;
        mode = "0644";
      };
      host_configuration.path = "${sshDir}/host_configuration";
      allowed_signers.path = "${config.xdg.configHome}/git/allowed_signers";
    };

    programs = {
      git = {
        signing.key = config.sops.secrets.ssh_ed25519_pub.path;
        settings.gpg.ssh.allowedSignersFile = config.sops.secrets.allowed_signers.path;
      };
      ssh.settings."*".IdentityFile = config.sops.secrets.ssh_ed25519.path;
    };
  })
  (lib.mkIf enableSecrets {
    sops.secrets.doppler_token = {
      path = "${config.xdg.dataHome}/doppler/token";
      mode = "0400";
    };
  })
]
