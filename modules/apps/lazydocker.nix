{
  lazydocker = {
    enable = true;
    settings = {
      gui = {
        language = "en";
        theme = {
          activeBorderColor = [
            "#cba6f7" # mauve
            "bold"
          ];
          inactiveBorderColor = [
            "#cdd6f4" # Text
          ];
          selectedLineBgColor = [
            "#313244" # Surface0
          ];
          optionsTextColor = [
            "#89b4fa" # Blue
          ];
        };
        returnImmediately = true;
        containerStatusHealthStyle = "icon";
      };
      logs = {
        timestamps = false;
      };
      # commandTemplates.dockerCompose = "docker compose";
    };
  };
}
