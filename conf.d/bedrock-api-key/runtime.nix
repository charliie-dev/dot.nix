{
  config,
  pkgs,
  lib,
  dopplerRun,
  sensitiveNames,
  grokShellPolicy,
  grokPolicySource,
}:
let
  python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  grokScript = pkgs.writeText "bedrock-grok.py" (builtins.readFile ./grok.py);
  claudeScript = pkgs.writeText "bedrock-claude.py" (builtins.readFile ./claude.py);
  keyAdminScript = pkgs.writeText "bedrock-key-admin.py" (builtins.readFile ./key_admin.py);
  configScript = pkgs.writeText "bedrock-grok-config.py" (builtins.readFile ./grok_config.py);
  verifyScript = pkgs.writeText "bedrock-verify.py" (builtins.readFile ./verify.py);
  processControl = pkgs.writeText "bedrock-process-control.py" (
    builtins.readFile ./process_control.py
  );
  emptyConfig = pkgs.writeText "bedrock-empty-aws-config" "";
  emptyCredentials = pkgs.writeText "bedrock-empty-aws-credentials" "";
  claudeOverlay = pkgs.writeText "claude-bedrock-settings.json" (
    builtins.toJSON {
      model = "opus[1m]";
      fallbackModel = [ "sonnet" ];
      env = {
        CLAUDE_CODE_USE_BEDROCK = "1";
        CLAUDE_CODE_USE_VERTEX = "";
        CLAUDE_CODE_USE_FOUNDRY = "";
        CLAUDE_CODE_USE_MANTLE = "";
        CLAUDE_CODE_USE_ANTHROPIC_AWS = "";
        CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD = "";
        CLAUDE_CODE_USE_GATEWAY = "";
        AWS_REGION = "ap-northeast-1";
        AWS_DEFAULT_REGION = "ap-northeast-1";
        AWS_CONFIG_FILE = toString emptyConfig;
        AWS_SHARED_CREDENTIALS_FILE = toString emptyCredentials;
        AWS_EC2_METADATA_DISABLED = "true";
        AWS_ACCESS_KEY_ID = "";
        AWS_SECRET_ACCESS_KEY = "";
        AWS_SESSION_TOKEN = "";
        AWS_SECURITY_TOKEN = "";
        ANTHROPIC_DEFAULT_FABLE_MODEL = "global.anthropic.claude-fable-5-1[1m]";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "global.anthropic.claude-opus-5-5[1m]";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "global.anthropic.claude-sonnet-5";
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "global.anthropic.claude-haiku-4-5-20251001-v1:0";
        ANTHROPIC_DEFAULT_FABLE_MODEL_NAME = "Bedrock Claude Fable 5.1";
        ANTHROPIC_DEFAULT_OPUS_MODEL_NAME = "Bedrock Claude Opus 5.5";
        ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = "Bedrock Claude Sonnet 5";
        ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME = "Bedrock Claude Haiku 4.5";
        ANTHROPIC_BASE_URL = "";
        ANTHROPIC_BEDROCK_BASE_URL = "";
        ANTHROPIC_FOUNDRY_BASE_URL = "";
        ANTHROPIC_FOUNDRY_RESOURCE = "";
        ANTHROPIC_VERTEX_BASE_URL = "";
        ANTHROPIC_VERTEX_PROJECT_ID = "";
        CLOUD_ML_REGION = "";
        ANTHROPIC_FOUNDRY_API_KEY = "";
        ANTHROPIC_FOUNDRY_AUTH_TOKEN = "";
        ANTHROPIC_API_KEY = "";
        ANTHROPIC_AUTH_TOKEN = "";
        ANTHROPIC_AWS_API_KEY = "";
        ANTHROPIC_CUSTOM_HEADERS = "";
        CLAUDE_CODE_OAUTH_TOKEN = "";
        GOOGLE_APPLICATION_CREDENTIALS = "";
        CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";
      };
    }
  );
  runtimeData = {
    home = config.home.homeDirectory;
    grok_home = "${config.xdg.configHome}/grok";
    claude_home = "${config.xdg.configHome}/claude";
    grok_policy = toString grokPolicySource;
    process_control = toString processControl;
    doppler_run = "${dopplerRun}/bin/doppler-run";
    doppler_binary = "${pkgs.doppler}/bin/doppler";
    python = "${python}/bin/python3";
    helper_path = "${lib.makeBinPath [ pkgs.coreutils ]}:/usr/bin:/bin";
    grok_binary = "grok";
    claude_binary = "claude";
    claude_overlay = toString claudeOverlay;
    empty_aws_config = toString emptyConfig;
    empty_aws_credentials = toString emptyCredentials;
    false_binary = "/usr/bin/false";
    sensitive_names = sensitiveNames;
    shell_policy = grokShellPolicy;
    project = "dot-nix";
    doppler_config = "dev_personal";
    api_host = "https://api.doppler.com";
  };
  runtime = pkgs.writeText "bedrock-runtime.json" (builtins.toJSON runtimeData);
  command =
    name: script: arguments:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${python}/bin/python3 -I ${script} ${runtime} ${arguments} "$@"
      '';
    };
  keyHelper = command "bedrock-api-key" grokScript "key";
  grokLauncher = command "grok-bedrock" grokScript "launch";
  claudeLauncher = command "claude-bedrock" claudeScript "";
  keyAdminRuntime = pkgs.writeText "bedrock-key-admin-runtime.json" (
    builtins.toJSON {
      inherit (runtimeData)
        doppler_binary
        project
        doppler_config
        api_host
        ;
    }
  );
  keyAdmin = pkgs.writeShellApplication {
    name = "bedrock-key-admin";
    text = ''
      exec ${python}/bin/python3 -I ${keyAdminScript} ${keyAdminRuntime} "$@"
    '';
  };
  configRuntime = pkgs.writeText "bedrock-config-runtime.json" (
    builtins.toJSON (
      runtimeData
      // {
        grok_key_helper = "${keyHelper}/bin/bedrock-api-key";
        claude_launcher = "${claudeLauncher}/bin/claude-bedrock";
      }
    )
  );
  configCommand = pkgs.writeShellApplication {
    name = "bedrock-grok-config";
    text = ''
      exec ${python}/bin/python3 -I ${configScript} ${configRuntime} "$@"
    '';
  };
  verifyCommand = pkgs.writeShellApplication {
    name = "bedrock-verify";
    text = ''
      exec ${python}/bin/python3 -I ${verifyScript} ${configRuntime} "$@"
    '';
  };
  manifest = pkgs.writeText "bedrock-build-manifest.json" (
    builtins.toJSON {
      grok_key_helper = "${keyHelper}/bin/bedrock-api-key";
      grok_launcher = "${grokLauncher}/bin/grok-bedrock";
      claude_launcher = "${claudeLauncher}/bin/claude-bedrock";
      key_admin = "${keyAdmin}/bin/bedrock-key-admin";
      grok_config = "${configCommand}/bin/bedrock-grok-config";
      verify = "${verifyCommand}/bin/bedrock-verify";
      inherit (runtimeData) doppler_run;
      inherit (runtimeData) python;
      grok_script = toString grokScript;
      claude_script = toString claudeScript;
      key_admin_script = toString keyAdminScript;
      key_admin_runtime = toString keyAdminRuntime;
      grok_policy = toString grokPolicySource;
      process_control = toString processControl;
      runtime_config = toString runtime;
      config_runtime = toString configRuntime;
      claude_overlay = toString claudeOverlay;
      empty_aws_config = toString emptyConfig;
      empty_aws_credentials = toString emptyCredentials;
    }
  );
  manifestCommand = pkgs.writeShellApplication {
    name = "bedrock-build-manifest";
    text = ''
      printf '%s\n' ${manifest}
    '';
  };
in
{
  packages = [
    keyHelper
    grokLauncher
    claudeLauncher
    keyAdmin
    configCommand
    verifyCommand
    manifestCommand
  ];
  files = {
    "grok/bin/bedrock-api-key".source = "${keyHelper}/bin/bedrock-api-key";
    "claude/bedrock-settings.json".source = claudeOverlay;
    "bedrock-api-key/build-manifest.json".source = manifest;
  };
}
