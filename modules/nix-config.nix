{ pkgs, ... }:
{
  nix = {
    package = pkgs.determinate-nix;
    checkConfig = true;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      use-xdg-base-directories = true;
      cores = 0;
      max-jobs = 10;
      auto-optimise-store = true;
      warn-dirty = false;
      http-connections = 50;
      trusted-users = "charles";
      download-buffer-size = 16777216000; # 16 GB

      # Determinate Nix-only settings (require pkgs.determinate-nix)
      lazy-trees = true;
      eval-cores = 0;
      # lazy-locks = true; # keep off: true omits NAR hashes from flake.lock,
      #   producing lock files that upstream/older Nix can't read (DS-only).
      #   Default false writes full NAR hashes = portable; upside of true is tiny.
    };
    # use nh to clean
    # gc = {
    #   automatic = false;
    #   options = "--delete-older-than 7d --max-freed $((1 * 1024**3))";
    # };
  };
}
