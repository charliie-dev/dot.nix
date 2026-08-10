#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup_file() {
  MATRIX_JSON="$BATS_FILE_TMPDIR/ssh-secret-matrix.json"
  export MATRIX_JSON
  nix eval --json --impure --expr "
    let
      f = builtins.getFlake \"git+file://$REPO\";
      hosts = import $REPO/hosts.nix;
      synthetic = enableSecrets: enableSshSecrets:
        f.lib.mkHomeConfiguration \"synthetic\" {
          system = \"x86_64-linux\";
          roles = [ ];
          homeDirectory = \"/home/charles\";
          inherit enableSecrets enableSshSecrets;
        };
      summarize = configuration:
        let
          cfg = configuration.config;
          packages = map (package: package.name or \"\") cfg.home.packages;
          activation = cfg.home.activation;
          sshConfig = cfg.home.file.\".ssh/config\".text;
        in {
          secrets = builtins.attrNames cfg.sops.secrets;
          hasDopplerPackage = builtins.any (name: builtins.match \"doppler-[0-9].*\" name != null) packages;
          hasDopplerWrapper = builtins.any (name: builtins.match \"doppler-run.*\" name != null) packages;
          hostInclude = builtins.elem \"~/.ssh/host_configuration\" cfg.programs.ssh.includes;
          identityFile = builtins.length (builtins.split \"IdentityFile\" sshConfig) > 1;
          signingKey = cfg.programs.git.signing.key or null;
          allowedSigners = cfg.programs.git.settings.gpg.ssh.allowedSignersFile or null;
          zshHostPreview = builtins.length (builtins.split \"host_configuration\" cfg.programs.zsh.initContent) > 1;
          authorizedEnabled = builtins.length (builtins.split \"--enabled\" activation.authorizedKeys.data) > 1;
          sopsSyncActive = activation.sops-nix-sync.data != \"\";
          sopsService = cfg.systemd.user.services ? sops-nix;
          sopsAgent = cfg.launchd.agents ? sops-nix-sync;
        };
    in {
      hosts = builtins.mapAttrs (name: _: summarize f.homeConfigurations.\${name}) hosts;
      falseFalse = summarize (synthetic false false);
      appOnly = summarize (synthetic true false);
    }
  " > "$MATRIX_JSON"
}

assert_matrix() {
  name="$1"
  app="$2"
  ssh="$3"
  if ! jq -e --arg name "$name" --argjson app "$app" --argjson ssh "$ssh" '
    .hosts[$name] as $h
    | ($h.secrets | sort) ==
        (if $app and $ssh then
           ["allowed_signers", "doppler_token", "host_configuration", "ssh_ed25519", "ssh_ed25519_pub"]
         elif $ssh then
           ["allowed_signers", "host_configuration", "ssh_ed25519", "ssh_ed25519_pub"]
         elif $app then ["doppler_token"] else [] end)
    and $h.hasDopplerPackage == $app
    and $h.hasDopplerWrapper == $app
    and $h.hostInclude == $ssh
    and $h.identityFile == $ssh
    and ($h.signingKey != null) == $ssh
    and ($h.allowedSigners != null) == $ssh
    and $h.zshHostPreview == $ssh
    and $h.authorizedEnabled == $ssh
    and $h.sopsSyncActive == ($app or $ssh)
    and ($h.sopsService or $h.sopsAgent) == ($app or $ssh)
  ' "$MATRIX_JSON" >/dev/null; then
    jq --arg name "$name" '.hosts[$name]' "$MATRIX_JSON" >&2
    return 1
  fi
}

@test "application-enabled fleet hosts retain both secret groups" {
  for host in \
    'charles@24041-LABNB01' 'charles@24041-LABNB01.local' \
    'charles@callisto' 'charles@pluto' 'charles@tmp-gpu'; do
    assert_matrix "$host" true true
  done
}

@test "RDSrv01 and all six shared aliases have SSH baseline without Doppler" {
  for host in \
    'charles@RDSrv01' 'charles@ra-lab' 'charles@nate-test' 'charles@testvm' \
    'charles@dcf-dev' 'charles@prod-deploy' 'charles@ra06-claude'; do
    assert_matrix "$host" false true
  done
}

@test "synthetic unspecified policy evaluates to both groups disabled" {
  jq -e '
    .falseFalse.secrets == []
    and (.falseFalse.hasDopplerPackage | not)
    and (.falseFalse.hasDopplerWrapper | not)
    and (.falseFalse.hostInclude | not)
    and (.falseFalse.identityFile | not)
    and (.falseFalse.zshHostPreview | not)
    and (.falseFalse.authorizedEnabled | not)
    and (.falseFalse.sopsSyncActive | not)
    and (.falseFalse.sopsService | not)
  ' "$MATRIX_JSON" >/dev/null
}

@test "synthetic application-only policy decrypts Doppler and leaves SSH inert" {
  jq -e '
    .appOnly.secrets == ["doppler_token"]
    and .appOnly.hasDopplerPackage
    and .appOnly.hasDopplerWrapper
    and (.appOnly.hostInclude | not)
    and (.appOnly.identityFile | not)
    and (.appOnly.zshHostPreview | not)
    and (.appOnly.authorizedEnabled | not)
    and .appOnly.sopsSyncActive
    and .appOnly.sopsService
  ' "$MATRIX_JSON" >/dev/null
}
