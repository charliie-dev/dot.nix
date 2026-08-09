{
  config,
  pkgs,
  lib,
  src,
  roles ? [ ],
  enableSecrets ? false,
  ...
}:
let
  inherit (import "${src}/modules/apps/_common.nix" { inherit pkgs; }) common_apps;
  role_pkgs = lib.concatMap (
    r: (import "${src}/modules/apps/roles/${r}.nix" { inherit config pkgs; }).packages
  ) roles;
  merged_pkgs = lib.unique (common_apps ++ role_pkgs);

  # Auto-discover program modules from modules/apps/.
  # Convention: <name>.nix returns { <name> = {...}; }; helpers prefix with _;
  # disabled modules use .bak suffix.
  appsDir = "${src}/modules/apps";
  appFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
  ) (builtins.readDir appsDir);
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
      raw = import "${appsDir}/${filename}";
      module = if lib.isFunction raw then raw appArgs else raw;
    in
    if lib.isAttrs module && module != { } then
      module
    else
      throw "modules/apps/${filename}: expected non-empty attrset, got ${builtins.typeOf module}";
  appModules = map loadApp (builtins.attrNames appFiles);
in
lib.mkMerge [
  {
    inherit (import "${src}/modules/nix-config.nix" { inherit pkgs; }) nix;

    manual = {
      manpages.enable = false;
      json.enable = false;
      html.enable = false;
    };

    home = {
      packages = merged_pkgs;
      preferXdgDirectories = true;
      shell.enableZshIntegration = true;
      sessionPath = [
        "/nix/var/nix/profiles/default/bin"
        "${config.home.homeDirectory}/.local/bin"
        "${config.xdg.dataHome}/cargo/bin"
        "${config.xdg.dataHome}/go/bin"
        "${config.xdg.dataHome}/pnpm"
        "${config.home.homeDirectory}/.local/share/mise/bin"
        "${config.home.homeDirectory}/.local/share/topgrade/bin"
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        "/opt/homebrew/bin"
        # gcloud components such as gke-gcloud-auth-plugin are not linked into
        # Homebrew's bin directory.
        "/opt/homebrew/share/google-cloud-sdk/bin"
      ];
      sessionVariables = {
        # XDG-aware tool homes shared by macOS and Linux.
        WGETRC = "${config.xdg.configHome}/wget/wgetrc";
        CARGO_HOME = "${config.xdg.dataHome}/cargo";
        RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
        GOPATH = "${config.xdg.dataHome}/go";
        GOMODCACHE = "${config.xdg.cacheHome}/go/mod";
        GONOPROXY = "github.com/nics-dp";
        GOPRIVATE = "github.com/nics-dp";
        _JAVA_OPTIONS = "-Djava.util.prefs.userRoot=${config.xdg.configHome}/java";
        DVDCSS_CACHE = "${config.xdg.dataHome}/dvdcss";
        # programs.npm currently produces $HOME//.config here when XDG mode is
        # enabled. Keep the native settings/file generation, but normalize the
        # exported path until the upstream module drops the extra slash.
        NPM_CONFIG_USERCONFIG = lib.mkForce "${config.xdg.configHome}/npm/npmrc";
        PNPM_HOME = "${config.xdg.dataHome}/pnpm";
        DOCKER_CONFIG = "${config.xdg.configHome}/docker";
        FFMPEG_DATADIR = "${config.xdg.configHome}/ffmpeg";
        ANSIBLE_CONFIG = "${config.xdg.configHome}/ansible/ansible.cfg";
        GNUPGHOME = "${config.xdg.dataHome}/gnupg";
        DOTNET_CLI_HOME = "${config.xdg.dataHome}/dotnet";
        IPYTHONDIR = "${config.xdg.configHome}/ipython";
        JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
        BUNDLE_USER_CONFIG = "${config.xdg.configHome}/bundle";
        BUNDLE_USER_CACHE = "${config.xdg.cacheHome}/bundle";
        BUNDLE_USER_PLUGIN = "${config.xdg.dataHome}/bundle";
        PARALLEL_HOME = "${config.xdg.configHome}/parallel";
        EDITOR = "nvim";
        VISUAL = "nvim";
        BUN_INSTALL = "${config.xdg.dataHome}/bun";
        D2_LAYOUT = "tala";
        TF_CLI_CONFIG_FILE = "${config.xdg.configHome}/terraform/terraformrc";
        DOPPLER_CONFIG_DIR = "${config.xdg.configHome}/doppler";
        HMD_CLI_CONFIG_DIR = "${config.xdg.configHome}/hackmd";
        SOPS_AGE_KEY_FILE = "${config.xdg.configHome}/age/keys.txt";

        # Code agents and their privacy/update policy. macOS GUI processes get
        # the required subset from the brew-env launchd adapter as well.
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        CODEX_HOME = "${config.xdg.configHome}/codex";
        COPILOT_HOME = "${config.xdg.configHome}/copilot";
        GROK_HOME = "${config.xdg.configHome}/grok";
        MCP_REMOTE_CONFIG_DIR = "${config.xdg.dataHome}/mcp-auth";
        ASIDE_HOME = "${config.xdg.dataHome}/aside";
        PI_CODING_AGENT_DIR = "${config.xdg.configHome}/pi";
        PI_CODING_AGENT_SESSION_DIR = "${config.xdg.dataHome}/pi/sessions";
        GROK_TELEMETRY_ENABLED = "0";
        GROK_FEEDBACK_ENABLED = "0";
        GROK_TELEMETRY_TRACE_UPLOAD = "0";
        GROK_DISABLE_AUTOUPDATER = "1";
        COPILOT_AUTO_UPDATE = "0";
        DO_NOT_TRACK = "1";
        CODEGRAPH_TELEMETRY = "0";
        CODEGRAPH_NO_UPDATE_CHECK = "1";

        # Cloud CLIs.
        AWS_SHARED_CREDENTIALS_FILE = "${config.xdg.configHome}/aws/credentials";
        AWS_CONFIG_FILE = "${config.xdg.configHome}/aws/config";
        AWS_CLI_SESSION_ID_DISABLED = "true";
        AWS_DEFAULT_OUTPUT = "json";
        AZURE_CONFIG_DIR = "${config.xdg.dataHome}/azure";
        OCI_CLI_CONFIG_FILE = "${config.xdg.configHome}/oci/config";
        OCI_CLI_RC_FILE = "${config.xdg.configHome}/oci/oci_cli_rc";
        OCI_CLI_PROFILE = "pluto";
        OCI_CLI_AUTH = "security_token";

        # Disable Determinate Nix telemetry
        # https://docs.determinate.systems/guides/telemetry/
        NIX_SENTRY_ENDPOINT = "";
        DETSYS_IDS_TELEMETRY = "disabled";
        # nh home switch is pure user-space; no sudo needed
        NH_ELEVATION_STRATEGY = "none";
      };
      file = {
        "self-made commands" = {
          enable = true;
          recursive = true;
          # 1. don't quote "../conf.d/Usercommand" for `source` needs to be `absolute path`
          # 2. use "${config.xdg.configHome}/home-manager/conf.d/Usercommand" will need to use `home-manager switch --impure`
          source = "${src}/conf.d/Usercommand";
          target = ".local/bin";
        };
      };
      activation = {
        initDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # GPG
          mkdir -p ${config.xdg.dataHome}/gnupg
          chmod 700 ${config.xdg.dataHome}/gnupg

          # Tool data dirs
          mkdir -p ${config.xdg.dataHome}/dotnet
        '';
      };
    };

    inherit
      (import "${src}/modules/xdg-config.nix" {
        inherit
          config
          pkgs
          lib
          src
          ;
      })
      xdg
      ;
    inherit (import "${src}/modules/catppuccin.nix") catppuccin;

    programs = lib.mkMerge appModules;

    services = {
      inherit (import "${src}/modules/services/home-manager.nix" { }) home-manager;
    };
  }
  (lib.mkIf enableSecrets (
    let
      sopsConfig = import "${src}/modules/sops.nix" { inherit config src; };
    in
    {
      inherit (sopsConfig) sops;

      home.activation.ssh = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        if [ -f ${config.home.homeDirectory}/.ssh/id_ed25519.pub ]; then
          if [ ! -f ${config.home.homeDirectory}/.ssh/authorized_keys ]; then
            touch ${config.home.homeDirectory}/.ssh/authorized_keys
          fi
          # Compare key type + body (cols 1-2), ignoring the comment field
          read -r ktype kbody _ < ${config.home.homeDirectory}/.ssh/id_ed25519.pub
          if ! grep -qF "$ktype $kbody" ${config.home.homeDirectory}/.ssh/authorized_keys; then
            cat ${config.home.homeDirectory}/.ssh/id_ed25519.pub >> ${config.home.homeDirectory}/.ssh/authorized_keys
          fi
        fi
      '';

      programs = {
        git.signing.key = "${config.sops.secrets.ssh_ed25519_pub.path}";
        git.settings.gpg.ssh.allowedSignersFile = "${config.sops.secrets.allowed_signers.path}";
        ssh.settings."*".IdentityFile = "${config.sops.secrets.ssh_ed25519.path}";
      };
    }
  ))
]
