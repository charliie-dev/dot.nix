# /etc/docker/daemon.json

Source: [11notes/RTFM](https://github.com/11notes/RTFM/blob/main/linux/container/docker/daemon.md)

*What is the Docker daemon.json configuration and why would I ever need to change it?*

The Docker daemon.json, located at `/etc/docker`, holds configuration data to configure the Docker Daemon (its runtime settings). The settings in this file will (or better should) overwrite any setting that was set by whatever installation method you took to install Docker.

Here is the daemon.json used in this RTFM repository:

```json
{
  "hosts": ["unix:///run/docker.sock"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "1",
    "labels": "production_status",
    "env": "os,customer"
  },
  "data-root": "/opt/docker",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.size=4G"
  ],
  "bip": "169.254.253.254/23",
  "fixed-cidr": "169.254.252.0/23",
  "default-address-pools":[
    {"base":"169.254.2.0/23","size":28},
    {"base":"169.254.4.0/22","size":28},
    {"base":"169.254.8.0/21","size":28},
    {"base":"169.254.16.0/20","size":28},
    {"base":"169.254.32.0/19","size":28},
    {"base":"169.254.64.0/18","size":28},
    {"base":"169.254.128.0/18","size":28},
    {"base":"169.254.192.0/19","size":28},
    {"base":"169.254.224.0/20","size":28},
    {"base":"169.254.240.0/21","size":28},
    {"base":"169.254.248.0/22","size":28}
  ],
  "mtu": 9000,
  "dns": ["DNS1","DNS2"],
  "registry-mirrors": ["https://docker.domain.com"]
}
```

# HOSTS AND LOGS

`hosts` tells the Docker Daemon to listen on this interface. This can be a network interface with an IP and a port or in this default, the UNIX socket exposed via the socket file located at `/run/docker.sock`. Anyone with access to this file, can directly interact with the Docker socket without any form of authentication. This means access to this file has to be very well guarded.

`log` and any of the adjacent options, simply tell Docker how to create the log files for each container. You can replace the standard logging to a file with logging to a collector, like Loki. The standard is to log to *.json* files. You can set how many log files should be kept (`max-file`) and how big a file can grow before it gets rotated (`max-size`). Setting `labels` means that the log will log all container labels that are called *production_status*, same goes for `env` with what variables you want to log.

# STORAGE

`data-root` is the most important one. It will tell Docker to store everything there, this has a huge impact on performance as well as the abilities you gain from that. It is recommended to store everything Docker related on an XFS formatted volume. Simply create a LVM volume and format it with XFS and mount it on `/opt/docker`.

`storage-driver` is the driver used and supported by the file system from `data-root`, since we want to use XFS to get the best performance and most capabilities, this defaults to overlay2.

`storage-opts.overlay2.size` lets us configure options of this storage driver. For the overlay2 driver we can set a default image size. This will limit any volume to a maximum of this size.

It is also advised to move the entire Docker installation to the `data-root`, not just the volumes and images.

# NETWORKING

`bip` and `fixed-cidr` is our default bridge network for containers that don't define a `networks:` property in the compose. `bip` is the default gateway used on this network.

`default-address-pools` are the IP address pools that Docker is allowed to create itself when using default settings for networking. The entire 169.254/16 subnet is split into network chunks. From these network chunks Docker is allowed to create a /28 subnet for each defined `networks:`. A /28 means that each defined network can only assign a maximum of 14 IP addresses. Since we can define multiple `networks:` however we like, this is not really a limitation.

`mtu` is the default MTU size used for each network defined. It must align with the physical switchport MTU. If your network is not using jumbo frames (aka MTU 9000), the default is 1500. **Must verify your entire network path (switches, routers) supports this MTU**, otherwise use 1500.

`dns` are the default DNS servers used for each container.

# NETWORKING 169.254.0.0/16

The 169.254/16 subnet is a special subnet that can be used on private networks. The subnet is non-routed and can only exist on a L2 network between devices which are all on the same L2 network. This makes it useless if you want to route networks, but very useful for containers, which are by definition, in their own flat L2 network. Using this subnet completely avoids IP collisions with corporate networks (`192.168.x.x`, `10.x.x.x`).

> **Caution:** Some applications (VPN, P2P) may ignore their interface if set to the 169.254/16 subnet. Make sure you set these subnets to their correct interface, like **tun** for a VPN or use another network mode like MACVLAN. Any app should always have a config option to define which interface to use to announce its public IP in P2P networks.

# MIRRORS

`registry-mirrors` is a very useful setting when you are concerned about the security of your docker hosts as well as being rate limited by Docker hub itself. With this setting you can tell Docker to download the images from these mirrors, instead of using the official ones. This gives you the ability to run a local mirror (for instance via [11notes/registry-proxy](https://github.com/11notes/docker-registry-proxy)). This mirror will download all the images on behalf of all your Docker hosts, and all your Docker hosts will pull all images from this mirror. This means we can take your Docker hosts offline, with no WAN access to increase security.

# CONCLUSION

You should never use the defaults provided to you by some distro or Docker itself, always adapt them to your use case and what works best for you.

**Defaults can never capture the complexity of an individual installation.**

> **Apply changes:** Modify `/etc/docker/daemon.json` then run `systemctl restart docker`.
