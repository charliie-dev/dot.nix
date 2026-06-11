# ROOTLESS - WHAT IS THAT?

Source: [11notes/RTFM](https://github.com/11notes/RTFM/blob/main/linux/container/image/rootless.md)

Everybody knows root and who he is, at least everybody that is using Linux. Most associate root with evil, which can be correct but is not necessarily true. So what does root have to do with rootless? A container image runs a process (preferably only a single process, but there can be exceptions). That process needs to be run as some user, just like any other process does.

Since the majority of users use Docker, we focus **only on Docker**, and the issues associated with it and rootless.

**I run Docker rootless so why should I care about this know-how?** Good point, you don't. This know-how targets the scenario where Docker daemon itself runs as root (the default).

# ROOTLESS - THE EVIL WITHIN

Docker will start each and every process inside a container **as root**, unless the creator of the container image told Docker to do otherwise or you yourself told Docker to do otherwise.

We can easily check this by comparing the Linux capabilities of root on the host vs. root inside a container:

**root on the Docker host**
```
Current: =ep
Bounding set =cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_linux_immutable,cap_net_bind_service,cap_net_broadcast,cap_net_admin,cap_net_raw,cap_ipc_lock,cap_ipc_owner,cap_sys_module,cap_sys_rawio,cap_sys_chroot,cap_sys_ptrace,cap_sys_pacct,cap_sys_admin,cap_sys_boot,cap_sys_nice,cap_sys_resource,cap_sys_time,cap_sys_tty_config,cap_mknod,cap_lease,cap_audit_write,cap_audit_control,cap_setfcap,cap_mac_override,cap_mac_admin,cap_syslog,cap_wake_alarm,cap_block_suspend,cap_audit_read,cap_perfmon,cap_bpf,cap_checkpoint_restore
```

vs.

**root inside a container on the same host**
```
Current: cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap=ep
Bounding set =cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap
```

vs.

**a normal user account (doesn't have to exist)**
```
Current: =
Bounding set =
```

We can see that root inside a container has a lot less caps than root on the host, but still has dangerous ones. `cap_net_raw` allows root to basically see all traffic on all interfaces assigned to the container. If you use `network_mode: host`, then root can see all network traffic of the entire host. It gets worse if you use `privileged: true` — you give root the option to escape to the host and do whatever as actual host root. We also see that the normal user has **no caps at all**, and that's actually what we want — not a handicapped root, but **no root at all**.

# ROOTLESS - DROP ROOT

Two options are at your disposal:

**Setting it yourself** is actually very easy to do:
```yaml
services:
  alpine:
    image: "alpine"
    user: "11420:11420"
```

Now Docker will execute all processes in the container as **11420:11420** and not as root. This only works if you take care of all permissions as well.

**Hoping the image maintainer set another user** — a container build file has a directive called `USER` which allows the image maintainer to set any user they like. It's usually the last line in any build file:

```dockerfile
# :: EXECUTE
  USER ${APP_UID}:${APP_GID}
  ENTRYPOINT ["/usr/local/bin/qbittorrent"]
  CMD ["--profile=/opt"]
```

**What about containers using the same UID/GID?** Don't worry about this scenario. Unless you accidentally mount that user's home directory into the container using the same UID/GID, there is no problem. Containers are isolated namespaces — they can't interact with a process started by a user on the same host.

**I don't need any of this, I use PUID and PGID thank you.** Well, you do actually. Using PUID/PGID still starts the image as root. Yes, root will then drop its privileges down to another user, the one you specified via PUID/PGID, but there is still a process in there running as root. **True rootless has no process run as root and doesn't start as root.** Even if root is only used briefly, why open yourself up to that brief risk?

**Bonus: security_opt** can be used to prevent a container image from gaining new privileges by privilege escalation:

```yaml
security_opt:
    - "no-new-privileges=true"
```

# ROOTLESS - SO ANY IMAGE IS ROOTLESS?

Sadly no. Actually **most images use root**. Using root means you can use `cap_chown` — this means you can chown folders and fix permission issues before the user of the image even notices that he forgot something. The sad part is you trade convenience for security.

Many images break when you switch from root to any combination of UID/GID, because the creators of these images did not anticipate you doing so or simply ignored the fact that some users like security more than they like convenience.

# ROOTLESS - CONCLUSION

Use rootless images, prefer rootless images. Do not trade your convenience for security. Running rootless images is no hassle, if anything, you learn how Linux file permissions work and how you mount a CIFS share with the correct UID/GID.

**Stay safe, stay rootless!**

# SOURCES
- [NIST SP 800-123/4.2.3 - Configure Resource Controls Appropriately](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-123.pdf)
- [NIST SP 800-190/3.1.2 - Image configuration defects](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
