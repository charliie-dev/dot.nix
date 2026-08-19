#!/usr/bin/env bats

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "unknown app roles report the valid choices" {
  run nix eval --impure --expr "
    let
      flake = builtins.getFlake \"path:$REPO\";
      configuration = flake.lib.mkHomeConfiguration \"role-test\" {
        system = builtins.currentSystem;
        roles = [ \"missing\" ];
        homeDirectory = \"$BATS_TEST_TMPDIR/home\";
      };
    in
    builtins.length configuration.config.home.packages
  "

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown app role 'missing'"* ]]
  [[ "$output" == *"dev-core, dev-extra, top"* ]]
}

@test "nvidiaGpu drives the NVIDIA integrations and capability package" {
  run nix eval --json --impure --expr "
    let
      flake = builtins.getFlake \"path:$REPO\";
      base = {
        system = \"x86_64-linux\";
        roles = [ ];
        homeDirectory = \"$BATS_TEST_TMPDIR/home\";
      };
      plain = flake.lib.mkHomeConfiguration \"plain\" base;
      nvidia = flake.lib.mkHomeConfiguration \"nvidia\" (base // { nvidiaGpu = true; });
      summarize = configuration: {
        hasNixgl = builtins.hasAttr \"nixgl\" configuration.pkgs;
        acceptLicense = configuration.pkgs.config.nvidia.acceptLicense or false;
        installScripts = configuration.config.targets.genericLinux.nixGL.installScripts or null;
        defaultWrapper = configuration.config.targets.genericLinux.nixGL.defaultWrapper or null;
        packageCount = builtins.length configuration.config.home.packages;
      };
      catalog = import $REPO/modules/apps/_packages.nix { pkgs = nvidia.pkgs; };
    in
    {
      plain = summarize plain;
      nvidia = summarize nvidia;
      packageDelta = (summarize nvidia).packageCount - (summarize plain).packageCount;
      roleNames = builtins.attrNames catalog.roles;
      capabilityCount = builtins.length (catalog.capabilities.nvidiaGpu or [ ]);
    }
  "
  [ "$status" -eq 0 ]

  result="$output"
  run jq -e '
    .plain.hasNixgl == false and
    .plain.acceptLicense == false and
    .plain.installScripts == null and
    .plain.defaultWrapper == "mesa" and
    .nvidia.hasNixgl == true and
    .nvidia.acceptLicense == true and
    .nvidia.installScripts == ["nvidia", "nvidiaPrime"] and
    .nvidia.defaultWrapper == "nvidiaPrime" and
    .packageDelta == 4 and
    .roleNames == ["dev-core", "dev-extra", "top"] and
    .capabilityCount == 1
  ' <<<"$result"
  [ "$status" -eq 0 ]
}

@test "nvidiaGpu rejects non-Linux hosts" {
  run nix eval --impure --expr "
    let
      flake = builtins.getFlake \"path:$REPO\";
      configuration = flake.lib.mkHomeConfiguration \"darwin-nvidia\" {
        system = \"aarch64-darwin\";
        roles = [ ];
        homeDirectory = \"$BATS_TEST_TMPDIR/home\";
        nvidiaGpu = true;
      };
    in
    builtins.length configuration.config.home.packages
  "

  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidiaGpu requires a Linux system"* ]]
}
