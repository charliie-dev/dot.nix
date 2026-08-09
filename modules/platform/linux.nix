{
  config,
  pkgs,
  lib,
  nixgl,
  gpuEnabled ? false,
  ...
}:
lib.mkIf pkgs.stdenv.isLinux {
  # Home Manager's generic Linux target supports every lib.platforms.linux
  # architecture, including aarch64-linux. nixGL remains GPU-host-only.
  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  }
  // lib.optionalAttrs gpuEnabled {
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
    sessionVariables = {
      TERMINFO_DIRS = config.systemd.user.sessionVariables.TERMINFO_DIRS;
      GTK_RC_FILES = "${config.xdg.configHome}/gtk-1.0/gtkrc";
      GTK2_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    };
  };

  # systemd user units don't source /etc/profile.d/nix.sh; nh shells out to `nix --version`.
  systemd.user.services.nh-clean.Service.Environment =
    "PATH=/nix/var/nix/profiles/default/bin:${config.home.profileDirectory}/bin";
}
