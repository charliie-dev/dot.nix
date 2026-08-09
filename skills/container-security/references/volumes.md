# DOCKER VOLUMES

Source: [11notes/RTFM](https://github.com/11notes/RTFM/blob/main/linux/container/docker/volumes.md)

*What are Docker volumes and why should I always prefer named volumes instead of bind mounts?*

**TL;DR:** Named volumes are the easiest way to work with persistent data and containers. They do all the heavy lifting for you. Use them by default! Do not use bind mounts, only use them if you have no other option available to you and even then, use them declared as a named volume!

# SYNOPSIS

Docker volumes are the best way to persist data from your containers in an ephemeral way, yet many people use them completely wrong.

## TYPES OF VOLUMES

Docker knows exactly three types of volumes/mounts:

**Named:** Docker will create the volume for you in the path specified in your daemon.json via the `data-root` property. Docker will create folders that do not exist and use the UID/GID that is present of the parent folder (if a parent folder is owned by 1000:1000 the sub folder will automatically be set to 1000:1000).

**Bind:** Docker will mount the volume from the host into the container. Docker **will not create any missing folders** and **will not set any permissions** like the UID/GID executing the process in the image.

**Tmpfs:** Docker will mount a tmpfs directory into the container. Not really persistent since the data is kept in RAM (tmpfs) and swap and not on disk. Use this type of volume for temporary data, like transcoding, logs and other files you do not need and can be re-created.

# BIND MOUNTS AND THE HORRORS BEYOND

Why is basically everyone using bind mounts and not named volumes? A lot of compose examples on the internet feature this type of volume by default.

The first problem: bind mounts are not managed by Docker but by you. You are responsible for creating the entire folder structure and setting all the correct permissions.

Another limiting factor: we can't limit the size of a bind mount via compose, but we must set this quota directly on the host. So instead of defining a 10GB limit in the compose, you must configure this directly on the host — which is anti-IaC, since you now have to manage two sets of configurations: The host and the compose file.

# NAMED VOLUMES AS THE SOLUTION

Named volumes solve all of this: Docker takes care that all folders used are automatically created if missing, it also sets the correct permissions on everything, and if set, applies the quota setting limiting the container to a specific size.

Why are people not using them? Most people do not know you can configure the `data-root` property. Another reason is that people think named volumes work only locally, while in fact you can use named volumes with any storage driver, be it NFS, CIFS or more exotic ones like S3.

The last reason people are against using named volumes: they think **they can't directly edit the files** in those volumes, **which again is totally wrong**. You can mount a named volume to infinite containers and expose them in infinite ways. You can also edit the files directly on the host.

# NAMED VOLUMES EXAMPLES

```yaml
# ╔═════════════════════════════════════════════════════╗
# ║                       NAMED                         ║
# ╚═════════════════════════════════════════════════════╝
name: "reverse-proxy"
services:
  traefik:
    image: "11notes/traefik"
    volumes:
      - "var:/traefik/var"
      - "plugins:/traefik/plugins"

volumes:
  var:
  plugins:

# ╔═════════════════════════════════════════════════════╗
# ║                       BIND                          ║
# ╚═════════════════════════════════════════════════════╝
volumes:
  var:
  plugins:
    driver_opts:
      type: none
      o: bind
      device: /path/to/local/volume

# ╔═════════════════════════════════════════════════════╗
# ║                        NFS                          ║
# ╚═════════════════════════════════════════════════════╝
volumes:
  var:
    driver_opts:
      type: "nfs"
      o: "addr=192.168.1.30,nolock,soft,nfsvers=4"
      device: ":/volume1/containers/traefik/var"
  plugins:

# ╔═════════════════════════════════════════════════════╗
# ║                       CIFS                          ║
# ╚═════════════════════════════════════════════════════╝
volumes:
  var:
    driver_opts:
      type: cifs
      o: username=service.traefik,password=${PASSWORD},domain=CONTOSO,uid=1000,gid=1000,dir_mode=0700,file_mode=0700
      device: //192.168.1.40/contoso/containers/traefik/var
  plugins:

# ╔═════════════════════════════════════════════════════╗
# ║                        S3                           ║
# ╚═════════════════════════════════════════════════════╝
volumes:
  var:
    driver: "s3fs"
    name: "bucket"
  plugins:

# ╔═════════════════════════════════════════════════════╗
# ║                       TMPFS                         ║
# ╚═════════════════════════════════════════════════════╝
services:
  traefik:
    volumes:
      - "var:/traefik/var"
    tmpfs:
      - "/traefik/plugins:uid=1000,gid=1000"

volumes:
  var:
```

# CONCLUSION

Now we know why named volumes are the better option and why we should always use them instead of bind mounts. The benefits are just too many to ignore them and the downsides are basically inexistent. Migrating from bind mounts to named volumes involves a simple copy process from the source directory, the bind mount, to the named volume, that's it.

**If you want IaC you need named volumes and not bind mounts. Keep your compose files portable and not dependent on folders on the host.**
