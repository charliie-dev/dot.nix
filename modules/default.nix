{
  imports = [
    ./core.nix
    ./apps
    ./platform
    ./runtime/mise.nix
    ./runtime/neovim.nix
    ./runtime/topgrade.nix
    ./secrets/doppler.nix
    ./secrets/sops.nix
  ];
}
