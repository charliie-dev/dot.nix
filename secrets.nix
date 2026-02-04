# NOTE: secrets.nix is not a module，DO NOT have `{ config, pkgs, ... }:`!!!
let
  # make key: age-keygen -o ~/.config/age/keys.txt
  # ehco key: age-keygen -y ~/.config/age/keys.txt
  charles = [
    "age1cc2n5xttywv2t86xmtpkg0fptgfkjflvqxzcrwavmpfjmkfrhsuskdh65q"
    "age1c0rk88eall59su5x4vfqrqtqskkdd3qnj5eyd93ve8wa6jmcx3dsmkzdx2"
  ];
  users = charles;

  oc_bot = "age1pzwzf6lqjsjgpys0jlwfc957xewhclfr7hxg5wftky0q4cunwsequqyysa";
  rdsrv01 = "age1hwpy5jpkm6kyvr2apppq5scceu5ypsqa8unptmrzry3pu37swygqcc7ca6";

  nics-demo-lab = "age1ma2h46jzrp3ux5gx6ad9l5yap7t60pl2jw0jevd9d6yn7k407yws3ws9sx";
  nate-test = "age10yxsamlz7rtc2lq4g5wtjdhktrycz4hlsyj7hrv86lrqaasumprsaskk0r";

  pg-proxy-dev = "age1mg3w0fvrcxn5hxea5wljdqshel3l2lykv9l62ux2nfnyt3ck4yzq6jq4v3";
  pg-primary-dev = "age17dzrdlw72pk9ne8rumparvmxg3tvrt5x3j8gen0tn3l7yptvr5jq9t7xwp";
  pg-replica1-dev = "age12xz85y9kya03wug9zgej04lfkta2lr6mfa6vlzjte4a722flygzqs0cyc3";
  pg-replica2-dev = "age1lqex949pjx6r05xe72majgps0wkerxksmekydgv292daprvfrdjq0g4eht";
  hosts = [
    pg-proxy-dev
    pg-primary-dev
    pg-replica1-dev
    pg-replica2-dev

    nics-demo-lab
    nate-test

    oc_bot
    rdsrv01
  ];
in
{
  "conf.d/ages/ssh_ed25519.age".publicKeys = users ++ hosts;
  "conf.d/ages/ssh_ed25519_pub.age".publicKeys = users ++ hosts;
  "conf.d/ages/host_configuration.age".publicKeys = users ++ hosts;
  "conf.d/ages/allowed_signers.age".publicKeys = users ++ hosts;

  # VPSs
  # Azure OpenAI
  "conf.d/ages/azure_openai_api_endpoint.age".publicKeys = users ++ hosts;
  "conf.d/ages/azure_openai_api_key.age".publicKeys = users ++ hosts;
  "conf.d/ages/azure_openai_api_version.age".publicKeys = users ++ hosts;
  # AWS
  "conf.d/ages/aws_region.age".publicKeys = users ++ hosts;
  "conf.d/ages/aws_access_key_id.age".publicKeys = users ++ hosts;
  "conf.d/ages/aws_secret_access_key.age".publicKeys = users ++ hosts;

  # D2 Studio
  "conf.d/ages/d2_token.age".publicKeys = users ++ hosts;
}
