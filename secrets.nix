# NOTE: secrets.nix is not a module，DO NOT have `{ config, pkgs, ... }:`!!!
let
  # make key: age-keygen -o ~/.config/age/keys.txt
  # ehco key: age-keygen -y ~/.config/age/keys.txt
  charles = [
    "age1cc2n5xttywv2t86xmtpkg0fptgfkjflvqxzcrwavmpfjmkfrhsuskdh65q"
    "age1c0rk88eall59su5x4vfqrqtqskkdd3qnj5eyd93ve8wa6jmcx3dsmkzdx2"
  ];
  users = charles;

  nics-demo-lab = "age1ma2h46jzrp3ux5gx6ad9l5yap7t60pl2jw0jevd9d6yn7k407yws3ws9sx";
  dcf-demo = "age12p7ng23relt5rkfp2xkk8nderzgwavfe3pun5e24xy6py2m8nuvsm7wr9q";
  pg-cluster = "age1s39em9vgexe2zgkntfdr0xpvnyunf6stwgy4ch2sd5ltdt25hu2q6x8rnx";
  nate-test = "age10yxsamlz7rtc2lq4g5wtjdhktrycz4hlsyj7hrv86lrqaasumprsaskk0r";
  nats-dev = "age1rv9c0d7kmu60j7v40l57uvlvr5p4jp8f6ym7tpvvh5wfwd4d5gfq4jged3";
  oc_bot = "age1pzwzf6lqjsjgpys0jlwfc957xewhclfr7hxg5wftky0q4cunwsequqyysa";
  rdsrv01 = "age1hwpy5jpkm6kyvr2apppq5scceu5ypsqa8unptmrzry3pu37swygqcc7ca6";
  hosts = [
    nics-demo-lab
    dcf-demo
    pg-cluster
    nats-dev
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
