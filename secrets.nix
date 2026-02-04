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
  pg-primary-dev = "age19tmhkq52a077pnrhu6svd05vm45wuffxfmkmgzdczgl03f3z5uusde3myg";
  pg-replica1-dev = "age1qrk5dqfnzhd9sy5ujd0p3q6gky0hztn3mrv5gzcj9yutcdu2552qflgy6s";
  pg-replica2-dev = "age1a8gvyt8zw5qm0t752cezs5e7dfmymxqlqvw59vgu9kjnhj0aks2q3e937e";
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
