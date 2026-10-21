{
  config,
  lib,
  pkgs,
  ...
}:
let
  source = pkgs.writeText "gws-mcp-auth.py" (
    builtins.readFile ../../../conf.d/Usercommand/gws-mcp-auth
  );
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  # Grok's MCP client has no headersHelper; it re-reads bearer_token_file on every
  # request. Keep those 1-hour access tokens fresh; refresh tokens stay in the Keychain.
  launchd.agents.gws-mcp-auth = {
    enable = true;
    # The login keychain is only reachable from the logged-in GUI session.
    domain = "gui";
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "-I"
        "${source}"
        "token-files"
      ];
      # 45 minutes; launchd runs a missed interval after wake.
      StartInterval = 2700;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/gws-mcp-auth.log";
    };
  };
}
