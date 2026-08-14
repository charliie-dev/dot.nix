{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  ...
}:
let
  inherit (import ./_common.nix { inherit pkgs; }) common_apps;
  rolePackages = lib.concatMap (
    role: (import (./roles + "/${role}.nix") { inherit config pkgs; }).packages
  ) roles;

  # Auto-discover program fragments from this directory. Convention:
  # <name>.nix returns { <name> = { ... }; }; helpers prefix with `_`.
  appFiles = lib.filterAttrs (
    name: type:
    type == "regular"
    && lib.hasSuffix ".nix" name
    && !(builtins.elem name [
      "default.nix"
      "catppuccin.nix"
      "patina.nix"
      "ssh.nix"
    ])
    && !(lib.hasPrefix "_" name)
  ) (builtins.readDir ./.);
  appArgs = {
    inherit
      config
      pkgs
      lib
      src
      ;
  };
  loadApp =
    filename:
    let
      raw = import (./. + "/${filename}");
      app = if lib.isFunction raw then raw appArgs else raw;
    in
    if lib.isAttrs app && app != { } then
      app
    else
      throw "modules/apps/${filename}: expected non-empty attrset, got ${builtins.typeOf app}";
in
{
  # Full app modules live beside the fragments but bypass programs.* wrapping.
  imports = [
    ./catppuccin.nix
    ./patina.nix
    ./ssh.nix
  ];

  home.packages = lib.unique (common_apps ++ rolePackages);
  programs = lib.mkMerge (map loadApp (builtins.attrNames appFiles));
}
