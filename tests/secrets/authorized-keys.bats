#!/usr/bin/env bats

load "../lib/home-config"

MODULE="$REPO/modules/secrets/sops.nix"
PIN='SHA256:DdWGvlMmBCptRDumMUS7sUjoD/W0BCOhLTQnF5Iw+m8'

setup() {
  require_home_config
  SEC03_TEST_TMPDIR="$(mktemp -d "$HOME/.sec03-authorized-keys.XXXXXXXX")"
  chmod 0700 "$SEC03_TEST_TMPDIR"
  export SEC03_TEST_TMPDIR
}

teardown() {
  case "${SEC03_TEST_TMPDIR:-}" in
    "$HOME"/.sec03-authorized-keys.*) rm -rf -- "$SEC03_TEST_TMPDIR" ;;
  esac
}

build_manager() {
  build_home_package manage-authorized-keys
}

manager_parts() {
  manager="$(build_manager)"
  script="$(sed -n 's/^exec python3 \([^ ]*manage-authorized-keys.py\).*/\1/p' "$manager/bin/manage-authorized-keys")"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$manager/bin/manage-authorized-keys" | head -n1)/python3"
}

@test "manager pins the approved fingerprint and activation ordering" {
  grep -qF "$PIN" "$MODULE"
  grep -q 'home.packages = \[ authorizedKeysManager \]' "$MODULE"
  grep -q 'home.activation.authorizedKeys = lib.hm.dag.entryAfter \[ "sops-nix-sync" \]' "$MODULE"
}

@test "observed orphan marker and Google duplicate are an exact no-op" {
  manager_parts
  run "$python" - "$script" <<'PY'
import os, runpy, subprocess, sys, tempfile
ns = runpy.run_path(sys.argv[1])
root = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
key = os.path.join(root, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip()
pin = ns['fingerprint_record'](record)
ns['fingerprint_record'].__globals__['PIN'] = pin
blob = record.split()[1]
fixture = (b'# google-ssh {"userName":"fixture"}\n' + record + b'\n' +
           b'# END home-manager managed key ' + pin.encode() + b'\n')
assert ns['available_bytes'](fixture, blob), 'unrestricted Google record was not classified'
assert fixture == fixture[:], 'fixture bytes changed'
print('orphan-google-noop-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = orphan-google-noop-ok ]
}

@test "exact record and canonical grammar are enforced" {
  manager_parts
  run "$python" - "$script" <<'PY'
import os, runpy, subprocess, sys, tempfile
ns = runpy.run_path(sys.argv[1])
root = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
def key(name):
    path = os.path.join(root, name)
    subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', path], check=True)
    return open(path + '.pub', 'rb').read().strip()
canonical = key('canonical')
other = key('other')
pin = ns['fingerprint_record'](canonical)
ns['fingerprint_record'].__globals__['PIN'] = pin
content, blob = ns['validate_canonical_bytes'](canonical + b'\r\n')
assert content == canonical
assert ns['available_bytes'](b' \t' + canonical + b'\r\n', blob)
assert not ns['available_bytes'](b'from="fixture.invalid" ' + canonical + b'\n', blob)
assert not ns['available_bytes'](b'command="true" ' + canonical + b'\n', blob)
assert not ns['available_bytes'](b'expiry-time="20990101" ' + canonical + b'\n', blob)
assert not ns['available_bytes'](b'restrict ' + canonical + b'\n', blob)
assert not ns['available_bytes'](b'cert-authority ' + canonical + b'\n', blob)
assert not ns['available_bytes'](b'ssh-ed25519-cert-v01@openssh.com ' + blob + b'\n', blob)
assert not ns['available_bytes'](b'ssh-ed25519 ' + other.split()[1] + b'\n', blob)
assert not ns['available_bytes'](b'xssh-ed25519 ' + blob + b'\n', blob)
assert not ns['available_bytes'](b'ssh-ed25519 ' + blob + b'\x00\n', blob)
assert not ns['available_bytes'](b'ssh-ed25519 ' + blob + b'\v\n', blob)
assert not ns['available_bytes'](b'ssh-ed25519 ' + blob + b'\f\n', blob)
# A printable comment pads the physical content to the exact conservative ceiling.
base = b'ssh-ed25519 ' + blob + b' '
line4096 = base + b'x' * (4096 - len(base))
line4097 = line4096 + b'x'
assert ns['available_bytes'](line4096 + b'\n', blob)
assert not ns['available_bytes'](line4097 + b'\n', blob)
invalid = [b'', b'\n', canonical + b'\n\n', canonical + b'\r\r\n',
           canonical + b'\r', canonical + b'\rX', canonical + b'\x00',
           canonical + b'\v', canonical + b'\f', canonical + b'\x7f',
           b'from="x" ' + canonical, other, line4097]
for value in invalid:
    try:
        ns['validate_canonical_bytes'](value)
    except SystemExit:
        pass
    else:
        raise AssertionError('invalid canonical input accepted')
print('exact-grammar-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = exact-grammar-ok ]
}

@test "append payload is LF-only append-only and idempotent" {
  manager_parts
  run "$python" - "$script" <<'PY'
import os, runpy, subprocess, sys, tempfile
ns = runpy.run_path(sys.argv[1])
root = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
key = os.path.join(root, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip()
ns['fingerprint_record'].__globals__['PIN'] = ns['fingerprint_record'](record)
_, blob = ns['validate_canonical_bytes'](record)
for original, prefix in [(b'', b''), (b'old\n', b''), (b'old\r\n', b''),
                         (b'old\r', b'\n'), (b'old', b'\n')]:
    payload = ns['append_payload'](original[-1:] if original else b'', record)
    assert payload == prefix + record + b'\n'
    combined = original + payload
    assert combined.startswith(original)
    assert ns['available_bytes'](combined, blob)
# Only LF splits records; hostile bytes remain inert and untouched.
hostile = b'bad\rpart\vpart\fpart\x00part\xff'
assert not ns['available_bytes'](hostile + b'\n', blob)
assert ns['append_payload'](hostile[-1:], record) == b'\n' + record + b'\n'
print('append-format-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = append-format-ok ]
}

@test "filesystem manager preserves bytes and metadata on no-op and appends once" {
  manager_parts
  run "$python" - "$script" <<'PY'
import hashlib, os, pwd, runpy, stat, subprocess, sys, tempfile, types
ns = runpy.run_path(sys.argv[1])
base = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
home = os.path.join(base, 'home'); ssh = os.path.join(home, '.ssh')
os.makedirs(ssh, mode=0o700); os.chmod(home, 0o700); os.chmod(ssh, 0o700)
key = os.path.join(base, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip()
g = ns['manage_authorized'].__globals__
g['PIN'] = ns['fingerprint_record'](record); g['HOME_DIR'] = home
ns['pwd'].getpwuid = lambda uid: types.SimpleNamespace(pw_dir=home)
os.environ['HOME'] = home
target = os.path.join(ssh, 'authorized_keys')
lock = target + '.lock'
fixture = b'# google fixture\n' + record + b'\n# END orphan\n'
open(target, 'wb').write(fixture); os.chmod(target, 0o644)
before = os.stat(target); digest = hashlib.sha256(fixture).digest()
result = ns['manage_authorized'](target, record, False)
after = os.stat(target)
assert result == 'no-op'
assert hashlib.sha256(open(target, 'rb').read()).digest() == digest
assert (before.st_uid, stat.S_IMODE(before.st_mode), before.st_nlink,
        before.st_mtime_ns, before.st_ctime_ns) == (after.st_uid, stat.S_IMODE(after.st_mode),
        after.st_nlink, after.st_mtime_ns, after.st_ctime_ns)
assert not os.path.exists(lock)
# Restricted presence does not satisfy the baseline and is preserved.
restricted = b'from="fixture.invalid" ' + record + b'\nunterminated'
open(target, 'wb').write(restricted); os.chmod(target, 0o600)
assert ns['manage_authorized'](target, record, False) == 'appended'
updated = open(target, 'rb').read()
assert updated == restricted + b'\n' + record + b'\n'
assert ns['manage_authorized'](target, record, False) == 'no-op'
assert open(target, 'rb').read() == updated
assert stat.S_IMODE(os.stat(lock).st_mode) == 0o600
print('filesystem-noop-append-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = filesystem-noop-append-ok ]
}

@test "disabled return dry-run path safety and primitive requirements" {
  manager_parts
  run "$python" - "$script" <<'PY'
import contextlib, io, os, runpy, sys, tempfile
ns = runpy.run_path(sys.argv[1])
# The CLI disabled branch must return before canonical/path/tool inspection.
old = sys.argv
sys.argv = ['manager', '--authorized', '/definitely/missing/unsafe/authorized_keys',
            '--public-key', '/definitely/unreadable']
ns['SSH_KEYGEN'] = '/definitely/unavailable'
ns['main']()
sys.argv = old
assert not os.path.exists('/definitely/missing')
# Required primitives fail closed rather than silently dropping O_NOFOLLOW.
saved = ns['os'].O_NOFOLLOW
ns['os'].O_NOFOLLOW = 0
try:
    try: ns['require_primitives']()
    except SystemExit: pass
    else: raise AssertionError('missing O_NOFOLLOW accepted')
finally:
    ns['os'].O_NOFOLLOW = saved
source = open(sys.argv[1], 'rb').read()
for forbidden in (b'os.replace(', b'os.unlink(', b'O_TRUNC', b'tempfile'):
    assert forbidden not in source
assert b'data.split(b"\\n")' in source
assert b'O_APPEND' in source and b'O_NOFOLLOW' in source and b'fcntl.flock' in source
print('disabled-and-primitives-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = disabled-and-primitives-ok ]
}

@test "write contract retries only EINTR and fails every positive short write" {
  manager_parts
  run "$python" - "$script" <<'PY'
import errno, os, runpy, sys, tempfile
ns = runpy.run_path(sys.argv[1])
fd, path = tempfile.mkstemp(dir=os.environ['SEC03_TEST_TMPDIR'])
real_write = ns['os'].write
try:
    calls = []
    def interrupted_then_full(fd, data):
        calls.append(len(data))
        if len(calls) == 1: raise InterruptedError(errno.EINTR, 'fixture')
        return real_write(fd, data)
    ns['write_once'](fd, b'fixture', interrupted_then_full)
    assert len(calls) == 2
    calls.clear()
    def short(fd, data):
        calls.append(len(data)); return real_write(fd, data[:1])
    try: ns['write_once'](fd, b'fixture', short)
    except ns['ShortWrite'] as exc: assert exc.written == 1
    else: raise AssertionError('positive short write accepted')
    assert len(calls) == 1
    calls.clear()
    def failed(fd, data): calls.append(len(data)); raise OSError(errno.EIO, 'fixture')
    try: ns['write_once'](fd, b'fixture', failed)
    except OSError: pass
    else: raise AssertionError('failed write accepted')
    assert len(calls) == 1
finally:
    os.close(fd); os.unlink(path)
print('write-contract-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = write-contract-ok ]
}

@test "activation dry-run delegates non-execution to DRY_RUN_CMD" {
  grep -q '\$DRY_RUN_CMD.*manage-authorized-keys' "$MODULE"
  run grep -q 'dry_run=--dry-run' "$MODULE"
  [ "$status" -eq 1 ]
}

@test "canonical deployment link and direct dry-run fail closed without mutation" {
  manager_parts
  run "$python" - "$script" <<'PY'
import errno, os, runpy, stat, subprocess, sys, tempfile, types
ns = runpy.run_path(sys.argv[1]); g = ns['manage_authorized'].__globals__
base = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
home = os.path.join(base, 'home'); ssh = os.path.join(home, '.ssh')
os.makedirs(ssh, mode=0o700); os.chmod(home, 0o700); os.chmod(ssh, 0o700)
g['HOME_DIR'] = home
ns['pwd'].getpwuid = lambda uid: types.SimpleNamespace(pw_dir=home)
os.environ['HOME'] = home
key = os.path.join(base, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip(); g['PIN'] = ns['fingerprint_record'](record)
# The deployment path must be the exact owned symlink to the expected safe terminal file.
terminal = os.path.join(base, 'terminal'); open(terminal, 'wb').write(record + b'\n')
deploy = os.path.join(ssh, 'id_ed25519.pub'); os.symlink(terminal, deploy)
g['PUBLIC_KEY_TARGET'] = terminal
for mode in (0o600, 0o644):
    os.chmod(terminal, mode)
    assert ns['read_expected_link'](deploy, terminal, ns['PUBLIC_KEY_MODES']) == record + b'\n'
os.chmod(terminal, 0o660)
try: ns['read_expected_link'](deploy, terminal, ns['PUBLIC_KEY_MODES'])
except SystemExit: pass
else: raise AssertionError('group-writable public key accepted')
os.unlink(deploy); os.symlink(os.path.join(base, 'wrong'), deploy)
try: ns['read_expected_link'](deploy, terminal, {0o644})
except SystemExit: pass
else: raise AssertionError('unexpected deployment target accepted')
os.unlink(deploy); os.symlink(terminal, deploy)
# Direct dry-run inspects state but creates no target or lock.
target = os.path.join(ssh, 'authorized_keys')
assert ns['manage_authorized'](target, record, True) == 'would append'
assert not os.path.exists(target) and not os.path.exists(target + '.lock')
# A newly created target must fail closed if its containing directory cannot fsync.
real_fsync = g['os'].fsync
def reject_directory_fsync(fd):
    if stat.S_ISDIR(os.fstat(fd).st_mode):
        raise OSError(errno.EINVAL, 'fixture')
    return real_fsync(fd)
g['os'].fsync = reject_directory_fsync
try:
    try: ns['manage_authorized'](target, record, False)
    except SystemExit: pass
    else: raise AssertionError('directory fsync failure was ignored')
finally:
    g['os'].fsync = real_fsync
assert os.path.exists(target)
print('deployment-and-dry-run-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = deployment-and-dry-run-ok ]
}

@test "unsafe directory target and lock metadata are rejected without repair" {
  manager_parts
  run "$python" - "$script" <<'PY'
import os, runpy, stat, subprocess, sys, tempfile, types
ns = runpy.run_path(sys.argv[1]); g = ns['manage_authorized'].__globals__
component = ns['validate_home_component']
other_uid = os.getuid() + 1000
component(types.SimpleNamespace(st_uid=other_uid, st_mode=stat.S_IFDIR | 0o755), False)
for fixture, final in [
    (types.SimpleNamespace(st_uid=other_uid, st_mode=stat.S_IFDIR | 0o775), False),
    (types.SimpleNamespace(st_uid=other_uid, st_mode=stat.S_IFDIR | 0o755), True),
]:
    try: component(fixture, final)
    except SystemExit: pass
    else: raise AssertionError('unsafe home component accepted')
base = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
home = os.path.join(base, 'home'); ssh = os.path.join(home, '.ssh')
os.makedirs(ssh, mode=0o700); os.chmod(home, 0o700); os.chmod(ssh, 0o700)
g['HOME_DIR'] = home
ns['pwd'].getpwuid = lambda uid: types.SimpleNamespace(pw_dir=home)
os.environ['HOME'] = home
key = os.path.join(base, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip(); g['PIN'] = ns['fingerprint_record'](record)
target = os.path.join(ssh, 'authorized_keys'); lock = target + '.lock'
def rejected(call):
    try: call()
    except SystemExit: return
    raise AssertionError('unsafe fixture accepted')
os.chmod(ssh, 0o755); rejected(lambda: ns['manage_authorized'](target, record, False)); os.chmod(ssh, 0o700)
external = os.path.join(base, 'external'); open(external, 'wb').write(b'external\n'); os.chmod(external, 0o600)
os.symlink(external, target); rejected(lambda: ns['manage_authorized'](target, record, False)); os.unlink(target)
open(target, 'wb').write(b'restricted\n'); os.chmod(target, 0o666)
rejected(lambda: ns['manage_authorized'](target, record, False)); assert (os.stat(target).st_mode & 0o777) == 0o666
os.chmod(target, 0o600); os.link(target, external + '.hard')
rejected(lambda: ns['manage_authorized'](target, record, False)); os.unlink(external + '.hard')
open(lock, 'wb').close(); os.chmod(lock, 0o644)
rejected(lambda: ns['manage_authorized'](target, record, False)); assert (os.stat(lock).st_mode & 0o777) == 0o644
print('unsafe-metadata-rejected-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = unsafe-metadata-rejected-ok ]
}

@test "cooperative writers serialize and external replacements are never overwritten" {
  manager_parts
  run "$python" - "$script" <<'PY'
import os, runpy, select, signal, subprocess, sys, tempfile, time, types
ns = runpy.run_path(sys.argv[1]); g = ns['manage_authorized'].__globals__
base = tempfile.mkdtemp(dir=os.environ['SEC03_TEST_TMPDIR'])
home = os.path.join(base, 'home'); ssh = os.path.join(home, '.ssh')
os.makedirs(ssh, mode=0o700); os.chmod(home, 0o700); os.chmod(ssh, 0o700)
g['HOME_DIR'] = home
ns['pwd'].getpwuid = lambda uid: types.SimpleNamespace(pw_dir=home)
os.environ['HOME'] = home
key = os.path.join(base, 'key')
subprocess.run([ns['SSH_KEYGEN'], '-q', '-t', 'ed25519', '-N', '', '-f', key], check=True)
record = open(key + '.pub', 'rb').read().strip(); g['PIN'] = ns['fingerprint_record'](record)
target = os.path.join(ssh, 'authorized_keys'); old = target + '.old'
def reset(value=b'restricted\n'):
    for path in (target, old, target + '.lock'):
        try: os.unlink(path)
        except FileNotFoundError: pass
    open(target, 'wb').write(value); os.chmod(target, 0o600)
def expect_failure(call):
    try: call()
    except SystemExit: return
    raise AssertionError('race unexpectedly succeeded')
# Two cooperating processes contend on the lock. Child 1 is held inside the
# critical section; child 2 must not reach its before-write hook until release.
def reap(pid, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited:
            return os.waitstatus_to_exitcode(status)
        time.sleep(0.02)
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
    raise AssertionError('child did not exit before timeout')
def release(fd):
    try: os.write(fd, b'1')
    except BrokenPipeError: pass
    os.close(fd)
reset()
ready1_r, ready1_w = os.pipe(); release_r, release_w = os.pipe()
pid1 = os.fork()
if pid1 == 0:
    os.close(ready1_r); os.close(release_w)
    def hold_first(event):
        if event == 'before-write':
            os.write(ready1_w, b'1'); os.read(release_r, 1)
    g['TEST_HOOK'] = hold_first
    try: ns['manage_authorized'](target, record, False)
    except BaseException: os._exit(1)
    os._exit(0)
os.close(ready1_w); os.close(release_r)
first_ready = bool(select.select([ready1_r], [], [], 5)[0])
if first_ready: os.read(ready1_r, 1)
ready2_r, ready2_w = os.pipe(); attempt_r, attempt_w = os.pipe(); proceed_r, proceed_w = os.pipe()
pid2 = os.fork()
if pid2 == 0:
    os.close(ready2_r); os.close(attempt_r); os.close(proceed_w)
    real_flock = g['fcntl'].flock
    def announcing_flock(fd, operation):
        os.write(attempt_w, b'1'); os.read(proceed_r, 1)
        return real_flock(fd, operation)
    def signal_second(event):
        if event == 'before-write': os.write(ready2_w, b'1')
    g['fcntl'].flock = announcing_flock; g['TEST_HOOK'] = signal_second
    try: ns['manage_authorized'](target, record, False)
    except BaseException: os._exit(1)
    os._exit(0)
os.close(ready2_w); os.close(attempt_w); os.close(proceed_r)
second_attempted_lock = bool(select.select([attempt_r], [], [], 5)[0])
if second_attempted_lock: os.read(attempt_r, 1)
release(proceed_w)
second_entered_while_locked = bool(select.select([ready2_r], [], [], 0.5)[0])
release(release_w)
second_entered_after_release = bool(select.select([ready2_r], [], [], 5)[0])
if second_entered_after_release: os.read(ready2_r, 1)
os.close(ready1_r); os.close(ready2_r); os.close(attempt_r)
statuses = (reap(pid1), reap(pid2))
assert first_ready and second_attempted_lock
assert not second_entered_while_locked and second_entered_after_release
assert statuses == (0, 0)
assert open(target, 'rb').read().split(b'\n').count(record) == 1
# Replacement before write is detected; replacement bytes survive untouched.
reset(); replacement = b'external-before-write\n'
def before_write(event):
    if event == 'before-write':
        os.rename(target, old); open(target, 'wb').write(replacement); os.chmod(target, 0o600)
g['TEST_HOOK'] = before_write
expect_failure(lambda: ns['manage_authorized'](target, record, False))
assert open(target, 'rb').read() == replacement
# Replacement after append but before final read is preserved and causes failure.
reset(); replacement = b'external-before-final\n'
def before_final(event):
    if event == 'before-final-read':
        os.rename(target, old); open(target, 'wb').write(replacement); os.chmod(target, 0o600)
g['TEST_HOOK'] = before_final
expect_failure(lambda: ns['manage_authorized'](target, record, False))
assert open(target, 'rb').read() == replacement
# A rewrite after the final observed read demonstrates the explicitly bounded claim.
reset(); replacement = b'external-after-final\n'
def after_final(event):
    if event == 'after-final-read':
        open(target, 'wb').write(replacement); os.chmod(target, 0o600)
g['TEST_HOOK'] = after_final
assert ns['manage_authorized'](target, record, False) == 'appended'
assert open(target, 'rb').read() == replacement
g['TEST_HOOK'] = lambda event: None
print('writer-races-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = writer-races-ok ]
}
