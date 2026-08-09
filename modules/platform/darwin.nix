{
  config,
  pkgs,
  lib,
  ...
}:
let
  upstreamSopsProgram = config.launchd.agents.sops-nix.config.Program;
  sopsLocked = pkgs.writeShellApplication {
    name = "sops-nix-locked";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export PATH="/usr/bin:/bin:$PATH"
            exec python3 - ${lib.escapeShellArg "${config.xdg.cacheHome}/sops-nix/decrypt.lock"} \
              ${lib.escapeShellArg upstreamSopsProgram} <<'PY'
      import fcntl
      import os
      import stat
      import sys

      lock_path, program = sys.argv[1:]
      parent = os.path.dirname(lock_path)
      os.makedirs(parent, mode=0o700, exist_ok=True)
      st = os.lstat(parent)
      if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
          raise SystemExit("sops-nix lock directory has an unsafe type")
      if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
          raise SystemExit("sops-nix lock directory has unsafe ownership or mode")
      flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
      fd = os.open(lock_path, flags, 0o600)
      try:
          fst = os.fstat(fd)
          if not stat.S_ISREG(fst.st_mode) or fst.st_uid != os.getuid():
              raise SystemExit("sops-nix lock file has an unsafe type or owner")
          os.fchmod(fd, 0o600)
          os.set_inheritable(fd, True)
          fcntl.flock(fd, fcntl.LOCK_EX)
          os.execv(program, [program])
      finally:
          os.close(fd)
      PY
    '';
  };
in
lib.mkIf pkgs.stdenv.isDarwin {
  targets.darwin = {
    # Homebrew manages all GUI applications.
    copyApps.enable = false;
    linkApps.enable = false;
    # null or one of "Bing", "DuckDuckGo", "Ecosia", "Google", "Yahoo"
    search = null;
    defaults = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.finder" = {
        AppleShowAllFiles = true;
        ShowPathBar = true;
        ShowStatusBar = true;
      };
      "com.apple.dock" = {
        autohide = true;
        # expose-group-apps = null;
        orientation = "bottom";
        # size-immutable = null;
        # tilesize = null;
      };
      "com.apple.menuextra.clock" = {
        Show24Hour = true;
        # 0 = When Space Allows, 1 = Always, 2 = Never
        ShowDate = 0;
        ShowDayOfMonth = true;
        ShowDayOfWeek = true;
        ShowSeconds = true;
      };
      "com.apple.Safari" = {
        IncludeDevelopMenu = true;
        AutoFillCreditCardData = false;
        AutoFillPasswords = true;
        AutoOpenSafeDownloads = false;
        ShowOverlayStatusBar = true;
      };
      NSGlobalDomain = {
        AppleMeasurementUnits = "Centimeters";
        AppleTemperatureUnit = "Celsius";
        AppleMetricUnits = true;
        AppleShowAllExtensions = true;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = null;
        NSAutomaticPeriodSubstitutionEnabled = true;
        NSAutomaticQuoteSubstitutionEnabled = true;
        NSAutomaticSpellingCorrectionEnabled = true;
      };
    };
    currentHostDefaults = {
      "com.apple.controlcenter" = {
        # Whether to show battery percentage in the menu bar.
        BatteryShowPercentage = false;
      };
    };
  };

  launchd.agents = {
    nh-clean = {
      # This scheduled background job runs after login; skip the wait wrapper so
      # Login Items shows its agent name instead of "sh".
      domain = "user";
      waitForNixStore = false;
      config = {
        # launchd inherits a minimal PATH; nh shells out to `nix --version`.
        EnvironmentVariables.PATH = "/nix/var/nix/profiles/default/bin:${config.home.profileDirectory}/bin";
        # Upstream HM passes extraArgs as one list element, which HM then shell-quotes
        # into a single token and clap errors out. mkForce (listOf merges by
        # concatenation, so a plain definition would append) with the args split.
        ProgramArguments = lib.mkForce (
          [
            "${pkgs.nh}/bin/nh"
            "clean"
            "user"
          ]
          ++ lib.splitString " " config.programs.nh.clean.extraArgs
        );
      };
    };
    # Disable the upstream asynchronous agent. The distinct login agent and
    # activation node both execute this same lock-serialized decrypt path.
    sops-nix = {
      enable = lib.mkForce false;
      waitForNixStore = false;
    };
    sops-nix-sync = {
      enable = true;
      domain = "gui";
      waitForNixStore = false;
      config = {
        Program = "${sopsLocked}/bin/sops-nix-locked";
        EnvironmentVariables = config.launchd.agents.sops-nix.config.EnvironmentVariables;
        KeepAlive = false;
        RunAtLoad = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/SopsNix/stdout";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/SopsNix/stderr";
      };
    };
  }
  //
    lib.genAttrs
      [
        "git-maintenance-hourly"
        "git-maintenance-daily"
        "git-maintenance-weekly"
      ]
      (_: {
        # These scheduled jobs run after login; avoid the wait wrapper so Login
        # Items shows each agent name instead of "sh".
        domain = "user";
        waitForNixStore = false;
      });

  # NOTE: the former `unloadHMAgentsBeforeSetup` pre-bootout workaround was
  # removed — current home-manager's setupLaunchAgents is domain-aware and
  # boots each agent out of its old domain before bootstrapping (the exact
  # EIO race the workaround guarded against).
}
