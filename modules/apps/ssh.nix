{
  config,
  lib,
  enableSshSecrets ? false,
  ...
}:
let
  # Pin the published host keys of the forges we clone from, so a fresh machine
  # never stops at the interactive "authenticity of host" prompt (it breaks
  # unattended git pulls, e.g. in topgrade). One read-only file per host under
  # ~/.ssh/known_hosts.d/. Sources (fingerprints checked against these pages):
  # - github.com: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  # - gitlab.com: https://docs.gitlab.com/user/gitlab_com/#ssh-known_hosts-entries
  # - hf.co:      https://huggingface.co/docs/hub/security-git-ssh (deprecated DSA key omitted)
  # On a key rotation ssh fails hard with "Offending key in ~/.ssh/known_hosts.d/<host>";
  # update this list and switch (or append the new key to ~/.ssh/known_hosts meanwhile).
  pinnedHostKeys = {
    "github.com" = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
    ];
    "gitlab.com" = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY="
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9"
    ];
    "hf.co" = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJjhgtT9FOQrsVSarIoPVI1jFMh3VSHdKfdqp/O776s"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBL0wtM52yIjm8gRecBy2wRyEMqr8ulG0uewT/IQOGz5K0ZPTIy6GIGHsTi8UXBiEzEIznV3asIz2sS7SiQ311tU="
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDtPB+snz63eZvTrbMY2Qt39a6HYile89JOum55z3lhIqAqUHxLtXFd+q+ED8izQvyORFPSmFIaPw05rtXo37bm+ixL6wDmvWrHN74oUUWmtrv2MNCLHE5VDb3+Q6MJjjDVIoK5QZIuTStlq0cUbGGxQk7vFZZ2VXdTPqgPjw4hMV7MGp3RFY/+Wy8rIMRv+kRCIwSAOeuaLPT7FzL0zUMDwj/VRjlzC08+srTQHqfoh0RguZiXZQneZKmM75AFhoMbP5x4AW2bVoZam864DSGiEwL8R2jMiyXxL3OuicZteZqll0qfRlNopKnzoxS29eBbXTr++ILqYz1QFqaruUgqSi3MIC9sDYEqh2Q8UxP5+Hh97AnlgWDZC0IhojVmEPNAc7Y2d+ctQl4Bt91Ik4hVf9bU+tqMXgaTrTMXeTURSXRxJEm2zfKQVkqn3vS/zGVnkDS+2b2qlVtrgbGdU/we8Fux5uOAn/dq5GygW/DUlHFw412GtKYDFdWjt3nJCY8="
    ];
  };
  knownHostsFile = host: ".ssh/known_hosts.d/${host}";
in
{
  home = {
    activation.sshControlDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.xdg.cacheHome}/ssh"
      chmod 700 "${config.xdg.cacheHome}/ssh"
    '';

    file = {
      # This include is evaluated before the encrypted host configuration. OpenSSH
      # uses the first value it obtains, so it overrides the legacy per-host
      # ~/.ssh/sockets ControlPath without duplicating every secret host block.
      # UpdateHostKeys deletes a host's entries from every non-first known_hosts
      # file and rewrites it via rename, which would replace the pinned symlinks
      # with plain files and block the next switch. Turn it off for pinned hosts.
      ".ssh/config.d/home-manager.conf".text = ''
        Host ${lib.concatStringsSep " " (lib.attrNames pinnedHostKeys)}
          UpdateHostKeys no

        Host *
          ControlPath ~/.cache/ssh/%C
      '';
    }
    // lib.mapAttrs' (
      host: keys:
      lib.nameValuePair (knownHostsFile host) {
        text = lib.concatMapStrings (key: "${host} ${key}\n") keys;
      }
    ) pinnedHostKeys;
  };

  programs.ssh = {
    enable = true;
    includes = [
      "~/.ssh/override_config"
      "~/.ssh/config.d/home-manager.conf"
    ]
    ++ lib.optionals enableSshSecrets [
      # `sunlei/zsh-ssh` cannot resolve an absolute deployment path.
      "~/.ssh/host_configuration"
    ];
    settings."*" = {
      AddKeysToAgent = "yes";
      IdentitiesOnly = true;
      Compression = true;
      ForwardAgent = false;
      HashKnownHosts = false;
      # Keep OpenSSH's two default files first (new keys are still written to
      # ~/.ssh/known_hosts) and append the read-only pinned files above.
      UserKnownHostsFile = lib.concatStringsSep " " (
        [
          "~/.ssh/known_hosts"
          "~/.ssh/known_hosts2"
        ]
        ++ map (host: "~/${knownHostsFile host}") (lib.attrNames pinnedHostKeys)
      );
      # OpenSSH only defaults this to yes while UserKnownHostsFile is unset.
      UpdateHostKeys = "yes";
      # IdentityFile is set by modules/secrets/sops.nix when secrets are enabled.
      ServerAliveInterval = 300;
      ServerAliveCountMax = 10;
    };
    enableDefaultConfig = false; # this option will be deprecated, so set it to false
  };
}
