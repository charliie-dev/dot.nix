{
  lazydocker = {
    enable = true;
    settings = {
      gui = {
        theme = {
          activeBorderColor = [
            "#a6e3a1" # Green
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
      # commandTemplates.dockerCompose = "docker compose";
    };
  };
}
