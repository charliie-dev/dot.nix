#!/usr/bin/env bats

load "../lib/home-config"

setup() {
  require_home_config
}

@test "determinate skips libgit2 checks but keeps boehm-gc checks" {
  graph="$BATS_TEST_TMPDIR/derivations.json"
  drv=$(nix eval --raw --impure --expr \
    "let f = builtins.getFlake \"path:$REPO\"; in f.homeConfigurations.\"$(home_config_name)\".activationPackage.drvPath")
  nix derivation show --recursive "$drv" > "$graph"

  jq -e '
    def enabled($derivation; $attribute):
      [
        $derivation.structuredAttrs[$attribute],
        $derivation.env[$attribute]
      ]
      | any(. == true or . == "1");

    .derivations as $derivations
    | [
        $derivations
        | to_entries[]
        | select((.value.name // "") | startswith("determinate-nix-fetchers-"))
        | .value.inputs.drvs
        | keys[]
        | select(($derivations[.].name // "") | startswith("libgit2-"))
      ] as $libgit2
    | [
        $derivations[]
        | select((.name // "") | startswith("boehm-gc-"))
        | enabled(.; "doCheck")
      ] as $boehm_gc_checks
    | [
        $libgit2[] as $drv
        | (
            enabled($derivations[$drv]; "doCheck")
            or enabled($derivations[$drv]; "doInstallCheck")
          )
      ] == [false]
      and (($boehm_gc_checks | length) > 0)
      and ($boehm_gc_checks | all)
  ' "$graph"
}
