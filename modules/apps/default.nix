{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  nvidiaGpu ? false,
  ...
}:
let
  packageSets = import ./_packages.nix { inherit pkgs; };
  validRoles = builtins.attrNames packageSets.roles;
  getRolePackages =
    role:
    if builtins.hasAttr role packageSets.roles then
      packageSets.roles.${role}
    else
      throw "unknown app role '${role}'; valid roles: ${lib.concatStringsSep ", " validRoles}";
  rolePackages = lib.concatMap getRolePackages roles;
  nvidiaPackages = lib.optionals nvidiaGpu packageSets.capabilities.nvidiaGpu;

  # Auto-discover program fragments from this directory. Convention:
  # <name>.nix returns { <name> = { ... }; }; helpers prefix with `_`.
  appFiles = lib.filterAttrs (
    name: type:
    type == "regular"
    && lib.hasSuffix ".nix" name
    && !(builtins.elem name [
      "default.nix"
      "aube.nix"
      "carapace.nix"
      "catppuccin.nix"
      "ghostty.nix"
      "glow.nix"
      "hunk.nix"
      "patina.nix"
      "ssh.nix"
      "terraform.nix"
      "tombi.nix"
      "wget.nix"
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
    ./aube.nix
    ./carapace.nix
    ./catppuccin.nix
    ./ghostty.nix
    ./glow.nix
    ./hunk.nix
    ./patina.nix
    ./ssh.nix
    ./terraform.nix
    ./tombi.nix
    ./wget.nix
  ];

  home.packages = lib.unique (packageSets.common ++ rolePackages ++ nvidiaPackages);
  programs = lib.mkMerge (map loadApp (builtins.attrNames appFiles));
}
