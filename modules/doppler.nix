{
  config,
  pkgs,
  lib,
  enableSecrets ? false,
  ...
}:
let
  dopplerDir = "${config.xdg.dataHome}/doppler";
  # Must match sops.nix doppler_token.path
  dopplerTokenPath = "${dopplerDir}/token";
in
lib.mkIf enableSecrets {
  home = {
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
            set -eu
            umask 077
            tmp=$(mktemp "${dopplerDir}/.env.XXXXXX")
            trap 'rm -f "$tmp"' EXIT HUP INT TERM
            if ${pkgs.doppler}/bin/doppler secrets download \
              --project dot-nix \
              --config dev_personal \
              --no-file \
              --format=env > "$tmp" 2>/dev/null \
              && [ -s "$tmp" ]; then
              chmod 600 "$tmp"
              mv -f "$tmp" "${dopplerDir}/env"
              trap - EXIT HUP INT TERM
            else
              echo "doppler secrets: download failed; keeping existing env" >&2
            fi
          )
        fi
      '';
    };
  };

  programs.zsh.envExtra = ''
    # Load Doppler secrets (application-layer)
    if [ -r "${dopplerDir}/env" ]; then
      set -a
      source "${dopplerDir}/env"
      set +a
    fi
  '';
}
