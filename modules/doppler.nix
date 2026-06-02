{
  config,
  pkgs,
  lib,
  ...
}:
let
  dopplerDir = "${config.xdg.dataHome}/doppler";
  # Must match sops.nix doppler_token.path
  dopplerTokenPath = "${dopplerDir}/token";
in
{
  doppler = {
    packages = [ pkgs.doppler ];

    # "sops-nix" is the sops-nix home-manager module's activation entry name
    # (renamed from the old "setupSecrets"). Verify with:
    #   grep -r "entryAfter\|entryBefore\|activation" <sops-nix-src>
    # Note: on Darwin sops-nix only launchctl-bootstraps its agent here; the
    # actual decryption runs async via launchd, so this ordering does not
    # guarantee a freshly-decrypted token within the same activation.
    activation = {
      doppler-secrets = lib.hm.dag.entryAfter [ "sops-nix" ] ''
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
