{
  imports = [
    ./core.nix
    ./apps
    ./platform
    ./runtime/docker.nix
    ./runtime/herdr.nix
    ./runtime/mise.nix
    ./runtime/neovim.nix
    ./runtime/topgrade.nix
    ./secrets/doppler.nix
    ./secrets/sops.nix
  ];
}
