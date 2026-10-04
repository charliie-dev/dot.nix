{ config, pkgs, ... }:
let
  python = pkgs.python3;
  parser = python.withPackages (ps: [
    ps.tree-sitter
    ps.tree-sitter-bash
  ]);
  policy = pkgs.writeText "bashka-agent-policy.toml" (
    builtins.readFile ../../conf.d/bashka/agent-policy.toml
  );
  entry = "${config.xdg.configHome}/bashka/agent-run";
  handler = "${config.xdg.configHome}/bashka/pre-tool-use";
  script =
    name: source: replacements:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      text =
        "#!${python}/bin/python3 -IS\n"
        + builtins.replaceStrings (map (key: ''"${key}"'') (
          builtins.attrNames replacements
        )) (builtins.attrValues replacements) (builtins.readFile source);
    };
in
{
  xdg.configFile = {
    "bashka/pre-tool-use".source = script "bashka-pre-tool-use" ../../conf.d/bashka/pre_tool_use.py {
      "@parserSite@" = builtins.toJSON "${parser}/${python.sitePackages}";
      "@entry@" = builtins.toJSON entry;
    };
    "bashka/post-tool-use-failure".source =
      script "bashka-post-tool-use-failure" ../../conf.d/bashka/post_tool_use_failure.py
        { };
    # Grok reads Claude's settings (~/.claude -> this config) for PostToolUseFailure, but
    # reports a non-zero shell exit as PostToolUse; register that event for Grok only.
    "grok/hooks/bashka.json".text = builtins.toJSON {
      hooks.PostToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${config.xdg.configHome}/bashka/post-tool-use-failure";
              timeout = 5;
            }
          ];
        }
      ];
    };
    "bashka/agent-run".source = script "bashka-agent-run" ../../conf.d/bashka/agent_run.py {
      "@binary@" =
        builtins.toJSON "${config.xdg.dataHome}/mise/installs/github-dmtr-kovalenko-bashka/latest/bashka";
      "@policy@" = builtins.toJSON (toString policy);
      "@bashBin@" = builtins.toJSON "${pkgs.bash}/bin";
    };
    "bashka/register-hooks".source =
      script "bashka-register-hooks" ../../conf.d/bashka/register_hooks.py
        {
          "@handler@" = builtins.toJSON handler;
          "@settings@" = builtins.toJSON "${config.xdg.configHome}/claude/settings.json";
        };
  };
}
