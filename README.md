# Azure Linux XFCE RDP container

This repository builds a container image that runs an XFCE desktop on Azure Linux 4.0 and serves it with xrdp.

Stock Azure Linux does not ship a desktop environment or xrdp. The Dockerfile starts from `mcr.microsoft.com/azurelinux-beta/base/core:4.0`, adds Fedora 43 package repositories for the desktop stack, and installs XFCE, xrdp, and xorgxrdp. Session scripts keep the desktop on X11, disable the xfwm4 compositor, force the RFX codec, and tear the session down when XFCE exits so a later login is not a black screen.

Use it as a local lab desktop from an RDP client. It is a container recipe, not an Azure Virtual Desktop image and not a Microsoft-supported desktop product. Longer build notes and troubleshooting are in [GUIDE.md](./GUIDE.md).

## Prerequisites

- An x86_64 machine. The Fedora repository URLs in the Dockerfile are `x86_64`.
- Docker with BuildKit, Podman, or [wslc](https://learn.microsoft.com/en-us/windows/wsl/wsl-container) on Windows. The Dockerfile writes the Fedora repo file with a heredoc (`<<'EOF'`). Current `docker build` uses BuildKit when the buildx plugin is installed. The legacy builder stops at that heredoc, so the repo file is never written and `dnf` cannot find XFCE or xrdp.
- Network access to Microsoft Container Registry and the Fedora package servers. The build pulls the base image and installs packages.
- About 2 GB of memory for the running container. The run commands below set that limit.

## Build and run

Run these from the repository root. The image tag is `azurelinux-xfce:rdp`. The container name in the examples is `azl-rdp`. Container port 3389 is published on host port 13392.

### Docker

```bash
docker build -t azurelinux-xfce:rdp .
docker rm -f azl-rdp 2>/dev/null || true
docker run -d --name azl-rdp -p 13392:3389 -m 2g azurelinux-xfce:rdp
```

### Podman

```bash
podman build -t azurelinux-xfce:rdp .
podman rm -f azl-rdp 2>/dev/null || true
podman run -d --name azl-rdp -p 13392:3389 -m 2g azurelinux-xfce:rdp
```

### wslc (Windows)

```powershell
wslc build -t azurelinux-xfce:rdp .
wslc remove -f azl-rdp 2>$null
wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp
```

There is no separate install step and no test suite, Makefile, or CI workflow in this repo.

The image defines a `HEALTHCHECK` (every 30 seconds, 5 second timeout, 25 second start period, 3 retries). It passes when `ss` shows a listener on port 3389. After the container has been up long enough for that check:

```bash
docker inspect --format '{{.State.Health.Status}}' azl-rdp
```

```bash
podman healthcheck run azl-rdp
```

The entrypoint prints a short ready line to the container log:

```bash
docker logs azl-rdp
```

## Usage

Connect an RDP client to `localhost:13392`.

| Field | Value |
| --- | --- |
| Address | `localhost:13392` |
| Username | `azureuser` |
| Password | `azureuser` |

On Windows:

```powershell
mstsc /v:localhost:13392
```

The session is X11 through xorgxrdp (`XDG_SESSION_TYPE=x11` in `startwm.sh`). It is not a Wayland session. If the client asks for a session type, choose Xorg.

`azureuser` is in the `wheel` group and has passwordless sudo via `/etc/sudoers.d/azureuser`.

Close the RDP window to disconnect. After **Log Out**, sign in again. `startwm.sh` starts `startxfce4` and exits when `xfce4-session` and `xfwm4` are gone, so xrdp does not reuse a dead session. `reconnectwm.sh` starts XFCE again if both are already gone when a client reconnects. The image sets `KillDisconnected=true` and `DisconnectedTimeLimit=0` in `sesman.ini` when that file exists.

Stop and start the same container:

```bash
docker stop azl-rdp
docker start azl-rdp
```

```powershell
wslc stop azl-rdp
wslc start azl-rdp
```

Optional: mount a host directory on the lab user's home so files survive a new container. The image does not declare a `VOLUME`; this is only a run flag.

```bash
docker run -d --name azl-rdp -p 13392:3389 -m 2g \
  -v "$HOME/azl-rdp-home:/home/azureuser" \
  azurelinux-xfce:rdp
```

A shell inside the running container, and a package-cache refresh with the image's package manager (`dnf5`, `dnf`, or `tdnf`):

```bash
docker exec -it azl-rdp bash
sudo dnf makecache
```

These credentials and the polkit rule that allows `wheel` and `azureuser` without a prompt are for a local lab. Do not publish port 3389 on a shared network with this password. The polkit rule file says not to use it on a multi-user production host. The base tag is `azurelinux-beta` (preview).

## Layout

```text
.
├── Dockerfile              # base image, Fedora repos, packages, user, xrdp config
├── docker-entrypoint.sh    # DNS fallback, dbus, polkitd, xrdp, keep-alive
├── startwm.sh              # XFCE session and logout watchdog
├── reconnectwm.sh          # restart XFCE if the session is gone on reconnect
├── skel/                   # copied to /etc/skel and into /home/azureuser
│   ├── .Xclients           # startxfce4
│   └── .config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
├── overlay/                # copied onto /
│   └── etc/
│       ├── polkit-1/rules.d/49-azureuser-nopasswd.rules
│       └── xdg/autostart/xfce-polkit.desktop
├── GUIDE.md
└── README.md
```

`skel/.config/.../xfwm4.xml` sets `use_compositing` to false and `vblank_mode` to off. `overlay` allows lab polkit actions and sets the XFCE polkit autostart entry to `Hidden=true`.

The primary `dnf` install includes `xrdp`, `xorgxrdp`, Xorg, `xfce4-session`, `xfwm4`, `xfdesktop`, `xfce4-panel`, `xfce4-settings`, `xfce4-terminal`, `xfce4-appfinder`, `thunar`, `xfce4-whiskermenu-plugin`, `mousepad`, fonts, and network tools (`iproute`, `iputils`, `net-tools`, `curl`, `wget`, `traceroute`, `bind-utils`, `nmap-ncat`, `procps-ng`). If that set fails, the Dockerfile retries a shorter list.

## License

The image label `org.opencontainers.image.licenses` is `MIT`. This repository has no `LICENSE` file.

The base image is Microsoft Azure Linux from Microsoft Container Registry. Desktop and RDP packages are installed from Fedora 43 because stock Azure Linux does not ship them.
