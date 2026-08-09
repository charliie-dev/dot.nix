{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkIf pkgs.stdenv.isDarwin {
  targets.darwin = {
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
      # StartCalendarInterval only fires long after login, so the /bin/wait4path
      # wrapper buys nothing and just hides the agent as "sh" in Login Items.
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
  }
  # Agents owned by upstream modules — only flip the wrapper off so they show
  # under their own name. All are `gui` domain, i.e. they start after GUI login,
  # by which point the (FileVault-encrypted) Nix Store volume is mounted.
  //
    lib.genAttrs
      [
        "git-maintenance-hourly"
        "git-maintenance-daily"
        "git-maintenance-weekly"
        "sops-nix"
      ]
      (_: {
        waitForNixStore = false;
      });

  # NOTE: the former `unloadHMAgentsBeforeSetup` pre-bootout workaround was
  # removed — current home-manager's setupLaunchAgents is domain-aware and
  # boots each agent out of its old domain before bootstrapping (the exact
  # EIO race the workaround guarded against).
}
