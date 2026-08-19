{
  config,
  pkgs,
  lib,
  nixgl,
  nvidiaGpu ? false,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  # Home Manager's generic Linux target supports every lib.platforms.linux
  # architecture, including aarch64-linux. nixGL remains GPU-host-only.
  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  }
  // lib.optionalAttrs nvidiaGpu {
    nixGL = {
      inherit (nixgl) packages;
      installScripts = [
        "nvidia"
        "nvidiaPrime"
      ];
      defaultWrapper = "nvidiaPrime";
      offloadWrapper = "nvidiaPrime";
      prime = {
        installScript = "nvidia";
        card = "1";
      };
    };
  };

  home = {
    packages = [ pkgs.ghostty.terminfo ];
    sessionVariables.TERMINFO_DIRS = config.systemd.user.sessionVariables.TERMINFO_DIRS;
  };

  # systemd user units don't source /etc/profile.d/nix.sh; nh shells out to `nix --version`.
  systemd.user.services.nh-clean.Service.Environment =
    "PATH=/nix/var/nix/profiles/default/bin:${config.home.profileDirectory}/bin";
}
