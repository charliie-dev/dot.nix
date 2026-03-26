{ config, pkgs, lib, ... }:
let
  secretDir = "${config.xdg.dataHome}/secrets_output";
  # Hardcode path to avoid circular dependency in plain function import
  # Must match sops.nix doppler_token.path
  dopplerTokenPath = "${secretDir}/doppler/token";
in
{
  doppler = {
    packages = [ pkgs.doppler ];

    # DAG entry name "setupSecrets" is the sops-nix home-manager module activation name
    # Verify with: grep -r "entryAfter\|entryBefore\|activation" <sops-nix-src>
    activation = {
      doppler-secrets = lib.hm.dag.entryAfter [ "setupSecrets" ] ''
        if [ -r "${dopplerTokenPath}" ]; then
          export DOPPLER_TOKEN="$(cat "${dopplerTokenPath}")"
          mkdir -p "${secretDir}/doppler"
          chmod 700 "${secretDir}/doppler"
          (
            umask 077
            ${pkgs.doppler}/bin/doppler secrets download \
              --project dot-nix \
              --config dev_personal \
              --no-file \
              --format=env > "${secretDir}/doppler/env" 2>/dev/null || true
          )
          chmod 600 "${secretDir}/doppler/env"
        fi
      '';
    };
  };
}
