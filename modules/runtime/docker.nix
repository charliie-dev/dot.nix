{
  config,
  lib,
  pkgs,
  ...
}:
let
  isLinux = pkgs.stdenv.isLinux;
  dockerConfigDir = "${config.xdg.configHome}/docker";
  dockerConfigFile = "${dockerConfigDir}/config.json";
  passwordStoreDir = "${config.xdg.dataHome}/password-store";
  gpgHome = "${config.xdg.dataHome}/gnupg";
  credentialsStore = if isLinux then "pass" else "osxkeychain";
  garRegistries = [ "asia-east1-docker.pkg.dev" ];
  credentialPackages = [
    pkgs.docker-credential-gcr
    pkgs.docker-credential-helpers
  ]
  ++ lib.optionals isLinux [ pkgs.pass ];
  activationPath = lib.makeBinPath (
    credentialPackages
    ++ [
      pkgs.coreutils
      pkgs.jq
    ]
    ++ lib.optionals isLinux [
      pkgs.gawk
      pkgs.gnupg
      pkgs.gnused
    ]
  );
in
{
  home = {
    packages = credentialPackages;
    sessionVariables = lib.mkIf isLinux {
      PASSWORD_STORE_DIR = passwordStoreDir;
    };

    activation.dockerCredentials = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        set -eu
        export PATH="${activationPath}:$PATH"
        export DOCKER_CONFIG="${dockerConfigDir}"
        umask 077

        mkdir -p "$DOCKER_CONFIG"
        chmod 700 "$DOCKER_CONFIG"

        ${lib.optionalString isLinux ''
          export PASSWORD_STORE_DIR="${passwordStoreDir}"
          export GNUPGHOME="${gpgHome}"
          mkdir -p "$PASSWORD_STORE_DIR" "$GNUPGHOME"
          chmod 700 "$PASSWORD_STORE_DIR" "$GNUPGHOME"

          key_uid='Home Manager Docker Credentials <docker-credentials@localhost>'
          if [ -s "$PASSWORD_STORE_DIR/.gpg-id" ]; then
            key_fpr=$(sed -n '/^[^#]/ { p; q; }' "$PASSWORD_STORE_DIR/.gpg-id")
            if [ -z "$key_fpr" ] || ! gpg --batch --list-secret-keys "$key_fpr" >/dev/null 2>&1; then
              echo "docker credentials: password store key is unavailable: $key_fpr" >&2
              exit 1
            fi
          else
            key_fpr=$(
              { gpg --batch --with-colons --list-secret-keys "$key_uid" 2>/dev/null || true; } \
                | awk -F: '$1 == "fpr" { print $10; exit }'
            )
            if [ -z "$key_fpr" ]; then
              gpg --batch --pinentry-mode loopback --passphrase "" \
                --quick-generate-key "$key_uid" rsa3072 encr 0
              key_fpr=$(
                gpg --batch --with-colons --list-secret-keys "$key_uid" \
                  | awk -F: '$1 == "fpr" { print $10; exit }'
              )
            fi
            pass init "$key_fpr" >/dev/null
          fi
        ''}

        config_file="${dockerConfigFile}"
        if [ ! -e "$config_file" ]; then
          printf '{}\n' > "$config_file"
        elif [ -L "$config_file" ]; then
          mutable_copy=$(mktemp "$DOCKER_CONFIG/.config.json.mutable.XXXXXX")
          cp --dereference "$config_file" "$mutable_copy"
          mv "$mutable_copy" "$config_file"
        fi

        if ! jq empty "$config_file" >/dev/null 2>&1; then
          echo "docker credentials: invalid JSON in $config_file" >&2
          exit 1
        fi

        new_config=$(mktemp "$DOCKER_CONFIG/.config.json.XXXXXX")
        trap 'rm -f "$new_config"' EXIT HUP INT TERM
        jq --arg store "${credentialsStore}" --argjson garRegistries '${builtins.toJSON garRegistries}' '
          .credsStore = $store
          | .credHelpers = reduce $garRegistries[] as $registry
              ((.credHelpers // {}); .[$registry] = "gcr")
        ' "$config_file" > "$new_config"
        chmod 600 "$new_config"
        mv "$new_config" "$config_file"
        trap - EXIT HUP INT TERM
      )
    '';
  };
}
