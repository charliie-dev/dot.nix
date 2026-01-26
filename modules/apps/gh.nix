{ pkgs, ... }:
{
  gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
      hosts = [ "https://github.com" ];
    };
    extensions = with pkgs; [
      gh-actions-cache
      # gh-cal
      # gh-contribs
      # github-copilot-cli
      # gh-dash
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
      aliases = { };
    };
  };
}
