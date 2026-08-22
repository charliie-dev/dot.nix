{ lib, ... }:
let
  suffixAliases = {
    json = "jless";
    md = "bat";
    txt = "bat";
    log = "bat";
    html = "open-default";
  };
  suffixAliasLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      suffix: command: "alias -s ${suffix}=${lib.escapeShellArg command}"
    ) suffixAliases
  );
in
{
  shellAliases = {
    grep = "grep --color=auto";
    sozsh = "exec zsh";
    rm = "rm -iv";
    mkdir = "mkdir -pv";
    ping = "ping -c 5";
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";
    bd = ''cd "$OLDPWD"'';
    nv = "nvim";
    wget = "wget2";
    zip = "ouch compress";
    unzip = "ouch decompress";
    cct = "claude-code-toggle";

    py = "TERM=xterm-256color python3";
    ls = "lsd -lAh";
    lg = "lazygit";
    lzd = "lazydocker";
    fzz = "zoxide query | fzf";
    fzp = "cat /etc/services | fzf";
    tree = "tree -CAF --dirsfirst";
    treed = "tree -CAFd";
    z = "zi";
    lj = "lazyjournal";
    # A writable ttyd shell must not be exposed on every network interface by
    # default. Use an SSH tunnel when remote access is needed.
    ttyd = "ttyd -p 9999 -i 127.0.0.1 -W zsh";

    mktar = "tar -cvf";
    mkbz2 = "tar -cvjf";
    mkgz = "tar -cvzf";
    untar = "tar -xvf";
    unbz2 = "tar -xvjf";
    ungz = "tar -xvzf";

    # Single-target aliases accept a container argument. Destructive all-target
    # variants are named explicitly.
    dstop = "docker stop";
    dstopall = "docker stop $(docker ps -aq)";
    drm = "docker rm";
    drmall = "docker rm $(docker ps -aq)";
    dprunevol = "docker volume prune";
    dprunesys = "docker system prune -a";
    ddelimages = "docker rmi $(docker images -q)";
    dexec = "docker exec -ti";
    dps = "docker ps -a";
    dpss = ''docker ps -a --format "table {{.Names}}\t{{.State}}\t{{.Status}}\t{{.Image}}" | (sed -u 1q; sort)'';
    ddf = "docker system df";
    dlogs = ''docker logs -tf --tail="50"'';

    dcrun = "docker compose";
    dclogs = ''docker compose logs -tf --tail="50"'';
    dcup = "docker compose up -d --build --remove-orphans";
    dcdown = "docker compose down --remove-orphans";
    dcrec = "docker compose up -d --force-recreate --remove-orphans";
    dcstop = "docker compose stop";
    dcrestart = "docker compose restart";
    dcstart = "docker compose start";
    dcpull = "docker compose pull";
  };

  shellGlobalAliases = {
    NE = "2>/dev/null";
    NO = ">/dev/null";
    NUL = ">/dev/null 2>&1";
    J = "| jq";
    C = "| clipcopy";
  };

  initContent = lib.mkOrder 1120 ''
    # Home Manager has no suffix-alias option.
    ${suffixAliasLines}
  '';
}
