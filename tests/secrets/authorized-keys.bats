#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
MODULE="$REPO/modules/secrets/sops.nix"
PIN='SHA256:DdWGvlMmBCptRDumMUS7sUjoD/W0BCOhLTQnF5Iw+m8'

build_manager() {
  nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"git+file://$REPO\"; ps = f.homeConfigurations.\"charles@24041-LABNB01\".config.home.packages; in builtins.head (builtins.filter (p: (p.name or \"\") == \"manage-authorized-keys\") ps)"
}

@test "manager pins the approved fingerprint outside the enable gate" {
  grep -qF "$PIN" "$MODULE"
  grep -q 'home.packages = \[ authorizedKeysManager \]' "$MODULE"
}

@test "public key accepts only the exact deployment link to a safe terminal file" {
  manager="$(build_manager)"
  script="$(sed -n 's/^exec python3 \([^ ]*manage-authorized-keys.py\).*/\1/p' "$manager/bin/manage-authorized-keys")"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$manager/bin/manage-authorized-keys" | head -n1)/python3"
  run "$python" - "$script" <<'PY'
import contextlib, io, os, runpy, tempfile
ns = runpy.run_path(__import__('sys').argv[1])
read_link = ns['read_expected_link']
root = tempfile.mkdtemp()
config = os.path.join(root, 'config', 'sops-nix')
generation = os.path.join(root, 'generation')
os.makedirs(config); os.makedirs(generation)
target = os.path.join(config, 'secrets', 'ssh_ed25519_pub')
terminal = os.path.join(generation, 'ssh_ed25519_pub')
open(terminal, 'wb').write(b'ssh-ed25519 SYNTHETIC\n')
os.chmod(terminal, 0o644)
os.symlink(generation, os.path.join(config, 'secrets'))
deploy = os.path.join(root, 'id_ed25519.pub')
os.symlink(target, deploy)
_, data = read_link(deploy, target, {0o644})
assert data == b'ssh-ed25519 SYNTHETIC\n'
def rejected(setup):
    try:
        setup()
        with contextlib.redirect_stderr(io.StringIO()): read_link(deploy, target, {0o644})
    except SystemExit:
        return
    raise AssertionError('unsafe fixture accepted')
os.unlink(deploy)
rejected(lambda: os.symlink(os.path.join(config, 'secrets', 'other'), deploy))
os.unlink(deploy)
rejected(lambda: open(deploy, 'wb').close())
os.unlink(deploy)
os.symlink(target, deploy); os.chmod(terminal, 0o600)
rejected(lambda: None)
print('public-key-link-fixtures-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = public-key-link-fixtures-ok ]
}

@test "identity delegates complete records to ssh-keygen without a shell" {
  grep -Fq 'SSH_KEYGEN = ' "$MODULE"
  grep -Fq '[SSH_KEYGEN, "-E", "sha256", "-lf", "-"]' "$MODULE"
  grep -Fq 'input=complete_record + b"\n"' "$MODULE"
  grep -Fq 'stderr=subprocess.DEVNULL' "$MODULE"
  ! grep -q 'shell=True' "$MODULE"
  ! grep -q 'KEY_PREFIXES' "$MODULE"
}

@test "quoted option fake key token cannot hide the actual pinned identity" {
  manager="$(build_manager)"
  script="$(sed -n 's/^exec python3 \([^ ]*manage-authorized-keys.py\).*/\1/p' "$manager/bin/manage-authorized-keys")"
  python="$(grep -o '/nix/store/[^:]*python3[^:]*/bin' "$manager/bin/manage-authorized-keys" | head -n1)/python3"
  run "$python" - "$script" <<'PY'
import os, runpy, subprocess, sys, tempfile
ns = runpy.run_path(sys.argv[1])
fingerprint = ns['fingerprint']
transform = ns['transform']
ssh_keygen = ns['SSH_KEYGEN']
root = tempfile.mkdtemp()
def make_key(name):
    path = os.path.join(root, name)
    subprocess.run([ssh_keygen, '-q', '-t', 'ed25519', '-N', '', '-f', path], check=True)
    record = open(path + '.pub', 'rb').read().strip()
    key_type, body, *_ = record.split()
    return key_type, body, record + b'\n'
actual_type, actual_body, actual_plain = make_key('actual')
other_type, other_body, other_plain = make_key('other')
adversarial = (b'command="echo ssh-ed25519 ' + other_body + b'" ' +
               actual_type + b' ' + actual_body + b' actual\n')
ordinary = b'from="fixture.invalid" ' + actual_type + b' ' + actual_body + b' ordinary\n'
escaped = (b'command="echo \\"quoted\\" ssh-ed25519 ' + other_body + b'" ' +
           actual_type + b' ' + actual_body + b' escaped\n')
unrelated = (b'command="echo ssh-ed25519 ' + actual_body + b'" ' +
             other_type + b' ' + other_body + b' unrelated\n')
for record in (adversarial, ordinary, escaped, unrelated):
    accepted = subprocess.run(
        [ssh_keygen, '-E', 'sha256', '-lf', '-'], input=record,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    assert accepted.returncode == 0
pin = fingerprint(actual_plain)
assert pin and fingerprint(adversarial) == pin
assert fingerprint(ordinary) == pin
assert fingerprint(escaped) == pin
assert fingerprint(unrelated) != pin
g = transform.__globals__
g['PIN'] = pin
g['BEGIN'] = ('# BEGIN home-manager managed key ' + pin).encode()
g['END'] = ('# END home-manager managed key ' + pin).encode()
source = b'before\n' + adversarial + b'after\n'
enabled = transform(source, True, actual_plain)
managed = g['BEGIN'] + b'\n' + adversarial + g['END'] + b'\n'
assert managed in enabled
assert enabled.count(actual_body) == 1
disabled = transform(source, False, None)
assert disabled == source, 'disabled hosts must not prune the pinned login key'
unrelated_source = b'before\n' + unrelated + b'after\n'
assert transform(unrelated_source, False, None) == unrelated_source
print('quoted-option-fingerprint-ok')
PY
  [ "$status" -eq 0 ]
  [ "$output" = quoted-option-fingerprint-ok ]
}

@test "marked block and ambiguous duplicate paths fail closed" {
  grep -q '# BEGIN home-manager managed key' "$MODULE"
  grep -q 'managed markers are malformed or overlapping' "$MODULE"
  grep -q 'differing matching legacy records require manual resolution' "$MODULE"
  grep -q 'managed and legacy matching records differ' "$MODULE"
}

@test "writer uses stable lock same-directory temporary and compare-before-rename" {
  grep -q 'args.authorized + ".lock"' "$MODULE"
  grep -q 'fcntl.LOCK_EX' "$MODULE"
  grep -q 'tempfile.mkstemp.*dir=parent' "$MODULE"
  [ "$(grep -c 'concurrent external edit detected' "$MODULE")" -eq 2 ]
  grep -q 'os.replace(temporary, args.authorized)' "$MODULE"
}

@test "dry-run returns before lock temp chmod and rename mutations" {
  grep -q 'if updated == original or args.dry_run:' "$MODULE"
  dry_line="$(grep -n 'if updated == original or args.dry_run:' "$MODULE" | cut -d: -f1)"
  lock_line="$(grep -n 'lock_path = args.authorized' "$MODULE" | cut -d: -f1)"
  [ "$dry_line" -lt "$lock_line" ]
}

@test "disabled invocation does not require decrypted public material" {
  grep -q 'activationArgs = lib.optionalString enableSecrets' "$MODULE"
  grep -q 'if args.enabled:' "$MODULE"
}
