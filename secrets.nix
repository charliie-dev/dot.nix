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

  dcf-demo = "age12p7ng23relt5rkfp2xkk8nderzgwavfe3pun5e24xy6py2m8nuvsm7wr9q";
  pg-cluster = "age1s39em9vgexe2zgkntfdr0xpvnyunf6stwgy4ch2sd5ltdt25hu2q6x8rnx";
  nats-dev = "age1t3uxkrvkrtequwj0deg784jjv7xfpjhjfdy5t8hkx34wd8f3xd9sl6n5ma";
  etcd-dev = "age184apecyns0ymv35tmczx0azclea75fvkkjsrnjrxjjnj9a6fheaqmmrcv9";
  haproxy-dev = "age1vh3eqwah8dw59g23sutrqya6ek7hpn2s4wrhzd950qsrx8we55tq6w687r";
  pg-primary-dev = "age1yg990z9hj74z6ypr55rv6tldw3jqw78lrrlvv2kels58j0pcdsjsh4n7xl";
  pg-replica1-dev = "age1z49hypwluaw4j2j5ljnlh508mutk0jpznkf0e57a3clnsvm6astsjyu87l";
  pg-replica2-dev = "age1enna5c7gnkfxzeqsnucrzjwjxhcspnlxh0ngs0s5tyfd7c574dlsrjx2kr";
  agent1-dev = "age1mcrz9sxem707s3te8637u5awmqthx25xu0sg0ck73y4e2eykjf9qskmynl";
  agent2-dev = "age15d8r9qtn4fx374rhf679ve7ka372u42dfajqvydhe9tu0y4hc30sntyy8s";
  platform-dev = "age10avltmxpnkz3dms7gdzvy7hw7r7f5g7mrqq8nn9xgk9fwcypucpqsja07g";
  hosts = [
    dcf-demo
    pg-cluster
    nats-dev
    etcd-dev
    haproxy-dev
    pg-primary-dev
    pg-replica1-dev
    pg-replica2-dev
    agent1-dev
    agent2-dev
    platform-dev

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
