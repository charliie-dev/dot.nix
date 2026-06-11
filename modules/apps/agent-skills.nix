{ lib, ... }:
# Declarative agent skills via Kyure-A/agent-skills-nix.
# The homeManagerModule itself is wired in flake.nix (modules list +
# extraSpecialArgs.inputs); this file only sets its options. The `input`
# string is resolved against specialArgs.inputs, so "google-skills" must
# match the flake input name.
#
# core.nix wraps every modules/apps/*.nix attrset under `programs` (line 300:
# `programs = lib.mkMerge appModules`), so this returns the bare `agent-skills`
# key — it becomes programs.agent-skills, matching the module's option.
{
  agent-skills = {
    enable = true;

    # google/skills is a plain repo (flake=false); its skills live under
    # skills/cloud/*, so discovery starts at the `skills` subdir and produces
    # nested ids like "cloud/bigquery-basics".
    sources.google = {
      input = "google-skills";
      subdir = "skills";
    };

    # Locally version-controlled skills living in this repo (modules/apps/skills/).
    # Flat layout (<name>/SKILL.md), so subdir stays at the default ".".
    sources.local.path = ./skills;

    # Pull every local skill (flat layout, discoverable as-is).
    skills.enableAll = [ "local" ];

    # The google source nests every skill under skills/cloud/<name>, so the
    # bundle lands them at skills/cloud/<name>/SKILL.md — one level too deep for
    # Claude Code's skill discovery, which only scans skills/<name>/SKILL.md.
    # So we DON'T enableAll "google" (that would re-create the invisible nested
    # tree). Instead cherry-pick the wanted skills here: explicit selection keyed
    # by the flat id we want (id = the attr name → dest = skills/<name>/), with
    # `path` pointing at the real "cloud/<name>" location under the source subdir.
    # To expose another google skill, add its name to this list.
    skills.explicit =
      lib.genAttrs
        [
          "bigquery-basics"
          "cloud-run-basics"
          "gemini-agents-api"
          "gemini-api"
          "gemini-interactions-api"
          "gke-basics"
          "google-cloud-networking-observability"
          "google-cloud-recipe-auth"
          "google-cloud-recipe-onboarding"
          "google-cloud-waf-cost-optimization"
          "google-cloud-waf-operational-excellence"
          "google-cloud-waf-performance-optimization"
          "google-cloud-waf-reliability"
          "google-cloud-waf-security"
          "google-cloud-waf-sustainability"
        ]
        (name: {
          from = "google";
          path = "cloud/${name}";
        });

    # Keep the default structure = "symlink-tree": an activation script rsyncs
    # the built bundle into each dest. Do NOT use "link" — its home.file path
    # feeds the bundle through a `types.path` option that strips the
    # derivation's string context, so the bundle never enters the build closure
    # and nothing is linked (verified: home-files.drv carried no bundle ref).
    # symlink-tree instead interpolates `${bundle}` into the script, which keeps
    # the context and builds the bundle.
    #
    # symlink-tree rsyncs with --delete, which would wipe hand-managed skills
    # kept in the same dirs. excludePatterns preserves them. Currently:
    #   claude   -> 5 hand-managed skills below
    #   codex    -> only ".system" (covered by the re-listed "/.system" default)
    #   copilot/opencode -> none yet
    # Add a "/<name>" entry here before hand-dropping a new skill into a target.
    excludePatterns = [
      "/.system"
      "/find-docs" # ctx7 setup auto-gen
    ];

    # dest must be an absolute path for the activation rsync; the literal $HOME
    # expands in bash at activation time (Nix passes it through verbatim). These
    # target this host's XDG dirs, matching CLAUDE_CONFIG_DIR / CODEX_HOME /
    # COPILOT_HOME (conf.d/zsh/exports.zsh). agent-skills' built-in copilot
    # default is ~/.copilot/skills and ignores COPILOT_HOME, hence the explicit
    # dest here.
    targets = {
      claude = {
        enable = true;
        dest = "$HOME/.config/claude/skills";
      };
      codex = {
        enable = true;
        dest = "$HOME/.config/codex/skills";
      };
      copilot = {
        enable = true;
        dest = "$HOME/.config/copilot/skills";
      };
      opencode = {
        enable = true;
        dest = "$HOME/.config/opencode/skills";
      };
    };
  };
}
