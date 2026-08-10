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
        import re
        import stat
        import subprocess
        import tempfile

        PIN = ${builtins.toJSON pinnedFingerprint}
        PUBLIC_KEY_TARGET = ${builtins.toJSON publicKeyTarget}
        SSH_KEYGEN = ${builtins.toJSON "${pkgs.openssh}/bin/ssh-keygen"}
        BEGIN = ("# BEGIN home-manager managed key " + PIN).encode()
        END = ("# END home-manager managed key " + PIN).encode()
        FINGERPRINT_RE = re.compile(r"^SHA256:[0-9A-Za-z+/]+={0,2}$")

        def fail(message):
            raise SystemExit("authorized_keys: " + message)

        def validate_dir(path, enabled, dry_run):
            try:
                st = os.lstat(path)
            except FileNotFoundError:
                if not enabled:
                    return False
                if dry_run:
                    fail("SSH directory would need creation before key validation")
                os.mkdir(path, 0o700)
                st = os.lstat(path)
            if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
                fail("SSH directory has an unsafe type")
            if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o022:
                fail("SSH directory has unsafe ownership or mode")
            return True

        def read_regular(path, allowed_modes, missing_ok=False):
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(path, flags)
            except FileNotFoundError:
                if missing_ok:
                    return None, b""
                fail("required key file is missing")
            except OSError:
                fail("file cannot be opened without following links")
            try:
                st = os.fstat(fd)
                if not stat.S_ISREG(st.st_mode):
                    fail("file has an unsafe type")
                if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) not in allowed_modes:
                    fail("file has unsafe ownership or mode")
                chunks = []
                while True:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                return st, b"".join(chunks)
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
            return read_regular(expected_target, allowed_modes)

        def fingerprint(record):
            complete_record = record.rstrip(b"\r\n")
            if not complete_record.strip():
                return None
            try:
                result = subprocess.run(
                    [SSH_KEYGEN, "-E", "sha256", "-lf", "-"],
                    input=complete_record + b"\n",
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

        def split_lines(data):
            return data.splitlines(keepends=True)

        def locate_block(lines):
            begins = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == BEGIN]
            ends = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == END]
            if not begins and not ends:
                return None
            if len(begins) != 1 or len(ends) != 1 or begins[0] >= ends[0]:
                fail("managed markers are malformed or overlapping")
            start, finish = begins[0], ends[0]
            records = [line for line in lines[start + 1:finish] if line.strip()]
            if len(records) != 1 or fingerprint(records[0]) != PIN:
                fail("managed block must contain exactly the pinned key")
            return start, finish, records[0]

        def transform(data, enabled, canonical):
            lines = split_lines(data)
            block = locate_block(lines)
            outside_indexes = set(range(len(lines)))
            managed_record = None
            if block:
                start, finish, managed_record = block
                outside_indexes.difference_update(range(start, finish + 1))
            matches = [(i, lines[i]) for i in sorted(outside_indexes) if fingerprint(lines[i]) == PIN]
            variants = {line.rstrip(b"\r\n") for _, line in matches}
            if len(variants) > 1:
                fail("differing matching legacy records require manual resolution")
            if block and variants and next(iter(variants)) != managed_record.rstrip(b"\r\n"):
                fail("managed and legacy matching records differ")

            # A disabled host never removes an existing record: the pinned key is
            # also the SSH login key, so pruning it here could lock out a host
            # whose SSH baseline is deliberately disabled.
            if not enabled:
                return data

            remove = {i for i, _ in matches}
            if block:
                start, finish, _ = block
                remove.update(range(start, finish + 1))
            remaining = b"".join(line for i, line in enumerate(lines) if i not in remove)

            record = managed_record
            if record is None and matches:
                record = matches[0][1]
            if record is None:
                record = canonical
            record = record.rstrip(b"\r\n") + b"\n"
            managed = BEGIN + b"\n" + record + END + b"\n"
            if block:
                prefix = b"".join(lines[:block[0]])
                suffix = b"".join(lines[block[1] + 1:] if block else [])
                suffix = b"".join(
                    line for line in split_lines(suffix) if fingerprint(line) != PIN
                )
                return prefix + managed + suffix
            separator = b"" if not remaining or remaining.endswith(b"\n") else b"\n"
            return remaining + separator + managed

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--enabled", action="store_true")
            parser.add_argument("--dry-run", action="store_true")
            parser.add_argument("--authorized", required=True)
            parser.add_argument("--public-key")
            args = parser.parse_args()
            parent = os.path.dirname(args.authorized)
            if not validate_dir(parent, args.enabled, args.dry_run):
                return

            canonical = None
            if args.enabled:
                _, public = read_expected_link(args.public_key, PUBLIC_KEY_TARGET, {0o644})
                records = [line for line in split_lines(public) if line.strip()]
                if len(records) != 1 or fingerprint(records[0]) != PIN:
                    fail("decrypted public key does not match the pinned fingerprint")
                canonical = records[0]

            original_st, original = read_regular(args.authorized, {0o600, 0o644}, True)
            updated = transform(original, args.enabled, canonical)
            if updated == original or args.dry_run:
                return

            lock_path = args.authorized + ".lock"
            lock_flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
            lock_fd = os.open(lock_path, lock_flags, 0o600)
            try:
                lock_st = os.fstat(lock_fd)
                if not stat.S_ISREG(lock_st.st_mode) or lock_st.st_uid != os.getuid():
                    fail("lock file has unsafe ownership or type")
                os.fchmod(lock_fd, 0o600)
                fcntl.flock(lock_fd, fcntl.LOCK_EX)
                current_st, current = read_regular(args.authorized, {0o600, 0o644}, True)
                original_id = None if original_st is None else (original_st.st_dev, original_st.st_ino)
                current_id = None if current_st is None else (current_st.st_dev, current_st.st_ino)
                if current_id != original_id or current != original:
                    fail("concurrent external edit detected")
                fd, temporary = tempfile.mkstemp(prefix=".authorized_keys.", dir=parent)
                try:
                    os.fchmod(fd, 0o600)
                    os.write(fd, updated)
                    os.fsync(fd)
                    os.close(fd)
                    fd = -1
                    verify_st, verify = read_regular(args.authorized, {0o600, 0o644}, True)
                    verify_id = None if verify_st is None else (verify_st.st_dev, verify_st.st_ino)
                    if verify_id != original_id or verify != original:
                        fail("concurrent external edit detected")
                    os.replace(temporary, args.authorized)
                    temporary = None
                    directory_fd = os.open(parent, os.O_RDONLY)
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
            finally:
                os.close(lock_fd)

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
      dry_run=
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        dry_run=--dry-run
      fi
      ${authorizedKeysManager}/bin/manage-authorized-keys \
        $dry_run ${activationArgs} \
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
