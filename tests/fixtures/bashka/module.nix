let
  flake = builtins.getFlake "path:${toString ../../..}";
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  root = builtins.getEnv "BASHKA_TEST_ROOT";
  module = import ../../../modules/runtime/bashka.nix {
    inherit pkgs;
    config.xdg = {
      configHome = "${root}/config";
      dataHome = "${root}/data";
    };
  };
  scripts =
    map
      (name: {
        inherit name;
        path = module.xdg.configFile."bashka/${name}".source;
      })
      [
        "pre-tool-use"
        "agent-run"
        "register-hooks"
      ];
in
assert root != "";
pkgs.linkFarm "bashka-hook-tests" (
  scripts
  ++ [
    {
      name = "python";
      path = pkgs.python3;
    }
    {
      name = "bash";
      path = pkgs.bash;
    }
  ]
)
