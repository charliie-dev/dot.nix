# DISTROLESS - WHAT IS THAT?

Source: [11notes/RTFM](https://github.com/11notes/RTFM/blob/main/linux/container/image/distroless.md)

It simply means that no binaries (executable programs) are present that are specifically tied to a Linux distribution. Container images are nothing more than a compressed archive containing everything the application needs to work. The question is, how much junk is in that zip file? A distroless image has **all junk removed** from its image. This means that your zip file contains only what the application needs to run, not one bit more.

# WHY DOES IT MAKE IT MORE SECURE?

Simply put, if there is less to attack, you have a harder time attacking something. That's why all ports on your firewall are by default closed. Why add a shell or curl to your image when your application doesn't need them to work? There is no benefit in having curl, ls, git, sh, wget and many more in your container image, but there could be a potential downside if any of these have a zero day or known CVE that can be exploited.

Someone might tell you: **"This does not matter!"** — since you run your app and not git. That is not entirely true. The app you run could have an exploit but not offer much in terms of functionality. For instance, the app can't make a web request, but the attacker gained access to the container's file system, hence he can now use curl or wget inside your image to further download more tools. These are commands that will try to download additional malicious code with tools available which the exploit thinks are present in any image (like curl, wget or sh). **If these tools are not available, the attack will already fail and the target will be marked as not vulnerable (to not waste time).**

**Nothing will protect you from a targeted attack!** If you are a target of an exploit or hacker group there is basically nothing you can do to protect yourself. You can only mitigate, but not prevent!

# DISTROLESS - TINY HEROES

Another advantage of a distroless image is its physical size. Since a distroless image has nothing in it that's not required to run the app, you save a lot of disk space in addition to reducing your attack surface.

| **image** | **size on disk** | **init default as** | **distroless** | supported architectures |
| ---: | ---: | :---: | :---: | :---: |
| 11notes/qbittorrent | 27MB | 1000:1000 | ✅ | amd64, arm64, armv7 |
| home-operations/qbittorrent | 111MB | 65534:65533 | ❌ | amd64, arm64 |
| hotio/qbittorrent | 159MB | 0:0 | ❌ | amd64, arm64 |
| qbittorrentofficial/qbittorrent-nox | 167MB | 0:0 | ❌ | 386, amd64, arm64, armv6, armv7, riscv64 |
| linuxserver/qbittorrent | 503MB | 0:0 | ❌ | amd64, arm64 |

Projects like [eStargz](https://github.com/containerd/stargz-snapshotter) try to solve the rampant container image growth by lazy loading images during download, instead of focusing on creating small images in the first place. **The solution is distroless, not lazy loading.**

**Do not confuse distroless with just image size!** The idea is still to have less binaries and libraries in the image that could be exploited.

# DISTROLESS - HOW CAN I USE IT?

Simply find a distroless image for the application you need. Creating a distroless image is a lot more work for the provider than it is for you to use it. You will basically never get a distroless image from the actual developer of the app — they ship their app often run as root and with a distro like Debian or Alpine.

# DISTROLESS - I GOT NO SHELL, WHAT NOW?

Since distroless containers have no shell, you can't `docker exec -ti` into them. Instead, enter the world of [nsenter](https://man7.org/linux/man-pages/man1/nsenter.1.html):

```bash
nsenter -t $(docker inspect -f '{{.State.Pid}}' adguard-server-1) -n netstat -tulpn
```

This will execute netstat attached to the defined PID in the namespace network, even though the image does not have netstat installed. You can execute any binary from the host, so you don't need to install debug tools into the image itself.

# DISTROLESS - LIMITATIONS

In a perfect world, every app could be run as distroless image, sadly that's not the case. Some apps require external libraries to be loaded at runtime, dynamically. Common signs you can't use distroless:

- App is based on Python
- App is based on node/deno with dynamic loaded libraries
- App is based on .NET core with inline Assembly calls

# DISTROLESS - CONCLUSION

The benefits are many, the downsides only a few and are not tied to actual distroless images but apps that can't be converted to distroless.

**Stay safe, stay distroless!**

# SOURCES
- [NIST SP 800-123/4.2.1 - Remove or Disable Unnecessary Services, Applications, and Network Protocols](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-123.pdf)
- [Docker Docs - Don't install unnecessary packages](https://docs.docker.com/build/building/best-practices/#dont-install-unnecessary-packages)
- [Docker Blog - Is Your Container Image Really Distroless?](https://www.docker.com/blog/is-your-container-image-really-distroless/)
