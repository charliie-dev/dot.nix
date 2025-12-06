{ config, src, ... }:
let
  secretDir = "${config.xdg.dataHome}/secrets_output";
in
{
  age = {
    identityPaths = [ "${config.xdg.configHome}/age/keys.txt" ];
    secrets = {
      ssh_ed25519 = {
        file = "${src}/conf.d/ages/ssh_ed25519.age";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "600";
      };
      ssh_ed25519_pub = {
        file = "${src}/conf.d/ages/ssh_ed25519_pub.age";
        path = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
        mode = "644";
      };
      ssh_host_config = {
        file = "${src}/conf.d/ages/host_configuration.age";
        path = "${config.home.homeDirectory}/.ssh/host_configuration";
      };
      git_allowed_signers = {
        file = "${src}/conf.d/ages/allowed_signers.age";
        path = "${config.xdg.configHome}/git/allowed_signers";
      };
      # Azure OpenAI
      azure_openai_api_endpoint = {
        file = "${src}/conf.d/ages/azure_openai_api_endpoint.age";
        path = "${secretDir}/azure/azure_openai_api_endpoint";
      };
      azure_openai_api_key = {
        file = "${src}/conf.d/ages/azure_openai_api_key.age";
        path = "${secretDir}/azure/azure_openai_api_key";
      };
      azure_openai_api_version = {
        file = "${src}/conf.d/ages/azure_openai_api_version.age";
        path = "${secretDir}/azure/azure_openai_api_version";
      };
      # AWS
      aws_region = {
        file = "${src}/conf.d/ages/aws_region.age";
        path = "${secretDir}/aws/aws_region";
      };
      aws_access_key_id = {
        file = "${src}/conf.d/ages/aws_access_key_id.age";
        path = "${secretDir}/aws/aws_access_key_id";
      };
      aws_secret_access_key = {
        file = "${src}/conf.d/ages/aws_secret_access_key.age";
        path = "${secretDir}/aws/aws_secret_access_key";
      };
      d2_token = {
        file = "${src}/conf.d/ages/d2_token.age";
        path = "${secretDir}/d2/d2_token";
      };
    };
  };
}
