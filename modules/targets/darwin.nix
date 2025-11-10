{
  darwin = {
    copyApps = {
      enable = true;
      enableChecks = true;
      directory = "Applications/Home Manager Apps";
    };
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
        AutoFillPasswords = false;
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
}
