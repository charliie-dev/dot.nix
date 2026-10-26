{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  # line-web's MCP listens only on pluto's 127.0.0.1:53426 and accepts only
  # `Host: 127.0.0.1:53426`, so the local port must be the same number.
  # Every option is on the command line: it beats ssh_config's first match and
  # does not depend on a Host block. ControlPath=none keeps ssh from riding an
  # existing master, where ServerAlive and the restart would act on another link.
  # No agent socket reaches launchd; the key file works without one (tested).
  launchd.agents.line-mcp-tunnel = {
    enable = true;
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "/usr/bin/ssh"
        "-N"
        "-o"
        "BatchMode=yes"
        "-o"
        "ControlPath=none"
        "-o"
        "ExitOnForwardFailure=yes"
        "-o"
        "ServerAliveInterval=30"
        "-o"
        "ServerAliveCountMax=3"
        "-o"
        "HostKeyAlias=oracle-pluto"
        "-L"
        "127.0.0.1:53426:127.0.0.1:53426"
        "charles@100.72.225.59"
      ];
      RunAtLoad = true;
      # ssh exits on a dead link (~90 s), a busy port or no Tailscale; launchd
      # restarts it. The throttle keeps an offline Mac from filling the log.
      KeepAlive = true;
      ThrottleInterval = 30;
      ProcessType = "Background";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/line-mcp-tunnel.log";
    };
  };
}
