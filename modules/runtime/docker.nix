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
  dockerLockFile = "${config.xdg.configHome}/.docker-config.lock";
  passwordStoreDir = "${config.xdg.dataHome}/password-store";
  gpgHome = "${config.xdg.dataHome}/gnupg";
  credentialsStore = if isLinux then "pass" else "osxkeychain";
  garRegistries = [ "asia-east1-docker.pkg.dev" ];
  credentialPackages = [
    pkgs.docker-credential-gcr
    pkgs.docker-credential-helpers
  ]
  ++ lib.optionals isLinux [ pkgs.pass ];
  flockBin = "${pkgs.util-linux}/bin/flock";
  # Darwin's fdesc filesystem reports a synthetic device number for /dev/fd.
  lockIdentityFormat = if isLinux then "%d:%i" else "%i";
  activationPath = lib.makeBinPath (
    credentialPackages
    ++ [
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
    ]
    ++ lib.optionals isLinux [
      pkgs.findutils
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
        # Home Manager dry-runs must not create directories, locks, or temporary files.
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          exit 0
        fi

        set -eu
        export PATH="${activationPath}:$PATH"
        export DOCKER_CONFIG="${dockerConfigDir}"
        umask 077

        die() {
          echo "docker credentials: $*" >&2
          exit 1
        }

        path_exists() {
          [ -e "$1" ] || [ -L "$1" ]
        }

        require_private_dir() {
          private_dir=$1
          path_exists "$private_dir" || die "required directory is missing: $private_dir"
          [ ! -L "$private_dir" ] || die "refusing symlink directory: $private_dir"
          [ -d "$private_dir" ] || die "refusing non-directory path: $private_dir"
          [ "$(stat -c %u -- "$private_dir")" = "$(id -u)" ] \
            || die "directory is not owned by the current user: $private_dir"
          [ "$(stat -c %a -- "$private_dir")" = 700 ] \
            || die "directory permissions must be 0700: $private_dir"
        }

        ensure_private_dir() {
          private_dir=$1
          if ! path_exists "$private_dir"; then
            mkdir -m 700 -- "$private_dir"
          fi
          require_private_dir "$private_dir"
        }

        require_private_file() {
          private_file=$1
          path_exists "$private_file" || die "required file is missing: $private_file"
          [ ! -L "$private_file" ] || die "refusing symlink file: $private_file"
          [ -f "$private_file" ] || die "refusing non-regular file: $private_file"
          [ "$(stat -c %u -- "$private_file")" = "$(id -u)" ] \
            || die "file is not owned by the current user: $private_file"
          [ "$(stat -c %a -- "$private_file")" = 600 ] \
            || die "file permissions must be 0600: $private_file"
          [ "$(stat -c %h -- "$private_file")" = 1 ] \
            || die "refusing multiply-linked file: $private_file"
        }

        config_file="${dockerConfigFile}"
        lock_file="${dockerLockFile}"
        ensure_private_dir "$DOCKER_CONFIG"

        if ! path_exists "$lock_file"; then
          # noclobber prevents an existing path from being followed or truncated.
          (set -C; : > "$lock_file") 2>/dev/null || true
        fi
        require_private_file "$lock_file"
        lock_path_identity=$(stat -Lc '${lockIdentityFormat}' -- "$lock_file")
        exec 9<> "$lock_file"
        lock_fd_identity=$(stat -Lc '${lockIdentityFormat}' -- /dev/fd/9)
        [ "$lock_path_identity" = "$lock_fd_identity" ] \
          || die "lock file changed while it was opened: $lock_file"

        # This lock serializes cooperating Home Manager activations only. Other
        # programs may edit Docker's config without taking it, so the writer also
        # compares source identity and content immediately before replacement.
        "${flockBin}" 9
        require_private_file "$lock_file"
        [ "$(stat -Lc '${lockIdentityFormat}' -- "$lock_file")" = "$lock_fd_identity" ] \
          || die "lock file was replaced while waiting: $lock_file"

        source_snapshot=
        new_config=
        cleanup() {
          [ -z "$source_snapshot" ] || rm -f -- "$source_snapshot"
          [ -z "$new_config" ] || rm -f -- "$new_config"
        }
        trap cleanup EXIT HUP INT TERM

        source_identity() {
          source_path=$1
          printf '%s:%s\n' \
            "$(stat -Lc '%d:%i:%s:%Y:%Z' -- "$source_path")" \
            "$(sha256sum -- "$source_path" | awk '{ print $1 }')"
        }

        capture_source() {
          source_snapshot=$(mktemp "$DOCKER_CONFIG/.config.json.source.XXXXXX")
          chmod 600 "$source_snapshot"
          if path_exists "$config_file"; then
            require_private_file "$config_file"
            expected_source=$(source_identity "$config_file")
            cat -- "$config_file" > "$source_snapshot"
            if ! path_exists "$config_file"; then
              return 1
            fi
            require_private_file "$config_file"
            [ "$(source_identity "$config_file")" = "$expected_source" ] || return 1
          else
            expected_source=absent
            printf '{}\n' > "$source_snapshot"
            ! path_exists "$config_file" || return 1
          fi
        }

        source_is_unchanged() {
          if [ "$expected_source" = absent ]; then
            ! path_exists "$config_file"
          else
            path_exists "$config_file" || return 1
            require_private_file "$config_file"
            [ "$(source_identity "$config_file")" = "$expected_source" ]
          fi
        }

        validate_config() {
          candidate=$1
          jq -e 'type == "object"' "$candidate" >/dev/null 2>&1 \
            || die "Docker config must be a JSON object: $config_file"
          jq -e '
            (.credsStore == null or (.credsStore | type) == "string")
            and
            (.credHelpers == null or (
              (.credHelpers | type) == "object"
              and all(.credHelpers[]; type == "string")
            ))
          ' "$candidate" >/dev/null 2>&1 \
            || die "Docker credsStore or credHelpers has an invalid type: $config_file"

          configured_store=$(jq -r '
            if .credsStore == null or .credsStore == "" then "unset"
            else .credsStore
            end
          ' "$candidate")
          if [ "$configured_store" = unset ]; then
            if jq -e '
              any(
                ((.auths? // {}) | .. | objects | to_entries[]?);
                (.key | test("^(auth|.*token)$"; "i"))
                and (.value != null and .value != "")
              )
            ' "$candidate" >/dev/null 2>&1; then
              die "refusing to set credsStore while inline auth/token credentials exist"
            fi
          elif [ "$configured_store" != "${credentialsStore}" ]; then
            die "refusing to replace conflicting credsStore '$configured_store'"
          fi

          jq -e --argjson registries '${builtins.toJSON garRegistries}' '
            . as $config
            | all($registries[];
                . as $registry
                | ($config.credHelpers == null
                  or ($config.credHelpers | has($registry) | not)
                  or $config.credHelpers[$registry] == "gcr")
              )
          ' "$candidate" >/dev/null 2>&1 \
            || die "refusing to replace a conflicting GAR credential helper"
        }

        ${lib.optionalString isLinux ''
          export PASSWORD_STORE_DIR="${passwordStoreDir}"
          export GNUPGHOME="${gpgHome}"
          key_uid='Home Manager Docker Credentials <docker-credentials@localhost>'

          usable_fingerprints_for_recipient() {
            recipient=$1
            now=$(date +%s)
            gpg --batch --with-colons --fixed-list-mode --list-secret-keys -- "$recipient" \
              2>/dev/null \
              | awk -F: -v now="$now" '
                  $1 == "sec" || $1 == "ssb" {
                    usable = ($2 !~ /^[redi]$/ && ($7 == "" || $7 == "0" || $7 > now) && $12 ~ /E/)
                    awaiting_fingerprint = 1
                    next
                  }
                  $1 == "fpr" && awaiting_fingerprint {
                    if (usable) print $10
                    awaiting_fingerprint = 0
                  }
                ' \
              | sort -u
          }

          usable_fingerprints_for_uid() {
            now=$(date +%s)
            gpg --batch --with-colons --fixed-list-mode --list-secret-keys 2>/dev/null \
              | awk -F: -v now="$now" -v wanted_uid="$key_uid" '
                  function flush_key(  i) {
                    if (has_uid) for (i = 1; i <= fingerprint_count; i++) print fingerprints[i]
                    delete fingerprints
                    fingerprint_count = 0
                    has_uid = 0
                  }
                  $1 == "sec" {
                    flush_key()
                    in_key = 1
                    usable = ($2 !~ /^[redi]$/ && ($7 == "" || $7 == "0" || $7 > now) && $12 ~ /E/)
                    awaiting_fingerprint = 1
                    next
                  }
                  $1 == "ssb" && in_key {
                    usable = ($2 !~ /^[redi]$/ && ($7 == "" || $7 == "0" || $7 > now) && $12 ~ /E/)
                    awaiting_fingerprint = 1
                    next
                  }
                  $1 == "fpr" && awaiting_fingerprint {
                    if (usable) fingerprints[++fingerprint_count] = $10
                    awaiting_fingerprint = 0
                    next
                  }
                  $1 == "uid" && in_key && $10 == wanted_uid { has_uid = 1 }
                  END { flush_key() }
                ' \
              | sort -u
          }

          count_fingerprints() {
            printf '%s\n' "$1" | awk 'NF { count++ } END { print count + 0 }'
          }

          require_one_fingerprint() {
            fingerprints=$1
            fingerprint_count=$(count_fingerprints "$fingerprints")
            [ "$fingerprint_count" -eq 1 ] \
              || die "expected exactly one usable secret encryption key, found $fingerprint_count"
            printf '%s\n' "$fingerprints"
          }

          read_gpg_recipient() {
            awk '
              !/^[[:space:]]*($|#)/ {
                sub(/^[[:space:]]+/, "")
                sub(/[[:space:]]+$/, "")
                print
                exit
              }
            ' "$1"
          }

          ensure_password_store() {
            ensure_private_dir "$PASSWORD_STORE_DIR"
            ensure_private_dir "$GNUPGHOME"
            gpg_id="$PASSWORD_STORE_DIR/.gpg-id"
            recipient=
            if path_exists "$gpg_id"; then
              require_private_file "$gpg_id"
              recipient=$(read_gpg_recipient "$gpg_id")
            fi

            if [ -n "$recipient" ]; then
              available=$(usable_fingerprints_for_recipient "$recipient")
            else
              encrypted_entry=$(find "$PASSWORD_STORE_DIR" -name '*.gpg' -print -quit)
              [ -z "$encrypted_entry" ] \
                || die "password store has encrypted entries but no logical .gpg-id recipient"
              available=$(usable_fingerprints_for_uid)
            fi

            # A host that deploys no secrets has no decrypted GPG key to initialise the
            # store with. Skip rather than die: this activation must not gate a switch on
            # hosts whose hosts.nix entry sets enableSecrets = false.
            if [ "$(count_fingerprints "$available")" -eq 0 ]; then
              echo "docker credentials: no usable secret encryption key; skipping password store" >&2
              return 0
            fi

            key_fpr=$(require_one_fingerprint "$available")
            [ -z "$recipient" ] || return 0

            pass init "$key_fpr" >/dev/null
            require_private_file "$gpg_id"
            initialized_recipient=$(read_gpg_recipient "$gpg_id")
            [ -n "$initialized_recipient" ] \
              || die "pass init did not create a logical .gpg-id recipient"
            require_one_fingerprint "$(usable_fingerprints_for_recipient "$initialized_recipient")" \
              >/dev/null
          }
        ''}

        attempt=1
        while [ "$attempt" -le 3 ]; do
          source_snapshot=
          new_config=
          if ! capture_source; then
            cleanup
            attempt=$((attempt + 1))
            continue
          fi

          validate_config "$source_snapshot"
          new_config=$(mktemp "$DOCKER_CONFIG/.config.json.XXXXXX")
          jq --arg store "${credentialsStore}" --argjson garRegistries '${builtins.toJSON garRegistries}' '
            .credsStore = $store
            | .credHelpers = reduce $garRegistries[] as $registry
                ((.credHelpers // {}); .[$registry] = "gcr")
          ' "$source_snapshot" > "$new_config"
          chmod 600 "$new_config"

          ${lib.optionalString isLinux "ensure_password_store"}

          if source_is_unchanged; then
            mv -f -- "$new_config" "$config_file"
            new_config=
            rm -f -- "$source_snapshot"
            source_snapshot=
            trap - EXIT HUP INT TERM
            exit 0
          fi

          cleanup
          attempt=$((attempt + 1))
        done

        die "Docker config changed repeatedly; refusing to overwrite it"
      )
    '';
  };
}
