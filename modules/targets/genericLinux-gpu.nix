{
  genericLinux = {
    enable = true;
    gpu = {
      # nixStateDirectory = "/nix/var/nix";
      enable = true;
      # https://home-manager-options.extranix.com/?query=targets.genericLinux.gpu.nvidia&release=master
      nvidia = {
        enable = true;
        version = "580.105.08"; # This version **must** match the version of the driver used by the host OS.
        # get sha256: nix store prefetch-file https://download.nvidia.com/XFree86/Linux-x86_64/@VERSION@/NVIDIA-Linux-x86_64-@VERSION@.run
        sha256 = "sha256-2cboGIZy8+t03QTPpp3VhHn6HQFiyMKMjRdiV2MpNHU=";
      };
    };
    # https://home-manager-options.extranix.com/?query=targets.genericLinux.nixGL&release=master
    nixGL = {
      # null or (list of (one of "mesa", "mesaPrime", "nvidia", "nvidiaPrime"))
      installScripts = [
        "nvidia"
        "nvidiaPrime"
      ];
      # main GPU
      defaultWrapper = "nvidiaPrime"; # one of "mesa", "mesaPrime", "nvidia", "nvidiaPrime"
      # secondary GPU
      offloadWrapper = "nvidiaPrime"; # one of "mesa", "mesaPrime", "nvidia", "nvidiaPrime"
      prime = {
        installScript = "nvidia"; # null or one of "mesa", "nvidia"
        # - a number, selecting the n-th non-default GPU;
        # - a PCI bus id in the form pci-XXX_YY_ZZ_U;
        # - a PCI id in the form vendor_id:device_id
        card = "1";
      };
    };
  };
}
