{
  config,
  pkgs,
  lib,
  ...
}:
let
  dopplerDir = "${config.xdg.dataHome}/doppler";
  # Hardcode path to avoid circular dependency in plain function import
  # Must match sops.nix doppler_token.path
  dopplerTokenPath = "${dopplerDir}/token";
in
{
  doppler = {
    packages = [ pkgs.doppler ];

    # DAG entry name "setupSecrets" is the sops-nix home-manager module activation name
    # Verify with: grep -r "entryAfter\|entryBefore\|activation" <sops-nix-src>
    activation = {
      doppler-secrets = lib.hm.dag.entryAfter [ "setupSecrets" ] ''
        export DOPPLER_CONFIG_DIR="${config.xdg.configHome}/doppler"
        if [ -r "${dopplerTokenPath}" ]; then
          export DOPPLER_TOKEN="$(cat "${dopplerTokenPath}")"
          mkdir -p "${dopplerDir}"
          chmod 700 "${dopplerDir}"
          (
            umask 077
            ${pkgs.doppler}/bin/doppler secrets download \
              --project dot-nix \
              --config dev_personal \
              --no-file \
              --format=env > "${dopplerDir}/env" 2>/dev/null || true
          )
          chmod 600 "${dopplerDir}/env"
        fi
      '';
    };
  };
}
