{ pkgs, ... }:
{
  packages = with pkgs; [
    iotop-c
    wavemon
  ];
}
