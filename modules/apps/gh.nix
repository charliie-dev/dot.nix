{ pkgs, ... }:
{
  gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
    };
    extensions = with pkgs; [
      # gh-cal
      # gh-contribs
      # gh-eco
      gh-f
      # gh-i
      # gh-markdown-preview
      gh-notify
      gh-poi
      gh-s
    ];
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
      telemetry = "disabled";
      # Already the default from gh 2.103; spelled out so logins keep the long-lived token.
      expiring_credentials = "disabled";
    };
  };
}
