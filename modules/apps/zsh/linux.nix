{ lib, pkgs, ... }:

lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  shellAliases = {
    ps = "ps auxf";
    openports = "ss -lntup";
  };

  # CUDA is a host capability rather than a general development role. Keep the
  # paths dormant on Linux machines without an NVIDIA driver.
  initContent = lib.mkOrder 1000 ''
    if (( $+commands[nvidia-smi] )); then
      export CUDA_CACHE_PATH="$XDG_CACHE_HOME/nv"
      [[ -d /usr/local/cuda/bin ]] && path=(/usr/local/cuda/bin $path)

      if [[ -d /usr/local/cuda/lib64 ]] &&
          (( ! $LD_LIBRARY_PATH[(I)/usr/local/cuda/lib64] )); then
        export LD_LIBRARY_PATH=/usr/local/cuda/lib64''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}
      fi
    fi
  '';
}
