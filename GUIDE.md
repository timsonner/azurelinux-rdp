# Azure Linux + XFCE + RDP — container guide (dnf / RHEL-family)

Standalone recipe for an **RDP desktop image** on **Azure Linux 4.0** (dnf-based). Suitable as a template for future dnf/RHEL-family desktop containers.

---

## What this is (one sentence)

**`mcr.microsoft.com/azurelinux-beta/base/core:4.0` + dnf (XFCE, xrdp, net tools from Fedora fill-in) + session scripts + home defaults under `skel/`.**

It is **not** a full OS install ISO, not Azure Virtual Desktop, and not Microsoft’s officially supported desktop product.

| Piece | Source |
|---|---|
| Base OS | Official MCR image `azurelinux-beta/base/core:4.0` |
| Desktop + RDP packages | **Fedora 43** repos layered with lower priority (Azure keeps core packages) |
| Home defaults | `skel/` → `/etc/skel` (xfwm4 compositor off, `.Xclients`) |
| Session / RDP glue | `startwm.sh`, `reconnectwm.sh`, `docker-entrypoint.sh` |
| RDP user | `azureuser` / `azureuser` |

---

## Why XFCE

| Desktop | Why for this image |
|---|---|
| **XFCE** | Light, X11-friendly, reliable under **xrdp + xorgxrdp** |
| GNOME | Wayland-first; awkward under classic xrdp |
| Plasma | Heavier; needs extra X11 compositor work under xorgxrdp |

Microsoft’s Azure VM RDP docs for other distros also commonly use **XFCE + xrdp**.

You do **not** need GDM for Windows RDP. GDM is a local display manager; **xrdp** owns the RDP path.

---

## Design choices (reuse this project later)

Keep these when basing a new container on this repo:

| Piece | Why |
|---|---|
| Slim base + install DE in Dockerfile | Rebuildable; no `commit` / export hacks |
| `skel/` for `/etc/skel` only | User defaults, not distro “theme packs” |
| `startwm.sh` + logout **watchdog** | Avoid black screen after Log Out |
| `reconnectwm.sh` | Best-effort recovery on reconnect |
| `KillDisconnected=true` in sesman | Tear down half-dead sessions |
| Entrypoint DNS fallback + dbus + xrdp | wslc/docker often have broken resolv.conf |
| Net tools in the image | `ping`, `dig`, `curl`, … work out of the box |
| X11 only (`xorgxrdp`) | Classic xrdp is not a Wayland path |
| Lab user with documented password | `azureuser` / `azureuser`; change for non-localhost |
| Host port mapping | e.g. `-p 13392:3389`, not public 3389 |

### `/etc` paths that matter

| Path | Role |
|---|---|
| `/etc/skel/` (from project `skel/`) | Defaults for new users + `azureuser` home seed |
| `/etc/skel/.config/xfce4/.../xfwm4.xml` | Compositor **off** under xorgxrdp |
| `/etc/skel/.Xclients` | `startxfce4` fallback |
| `/etc/xrdp/startwm.sh` | Session start + watchdog |
| `/etc/xrdp/reconnectwm.sh` | Reconnect recovery |
| `/etc/xrdp/sesman.ini` | `KillDisconnected=true` (patched at build) |
| `/etc/X11/Xwrapper.config` | `allowed_users=anybody` |
| `/etc/yum.repos.d/fedora43-desktop.repo` | XFCE/xrdp packages (Azure has no DE) |
| `/etc/sudoers.d/azureuser` | Passwordless sudo for lab |

---

## Project layout

```text
azurelinux-rdp/
├── Dockerfile                 # Azure base + Fedora fill-in + XFCE + xrdp
├── docker-entrypoint.sh       # DNS, dbus, xrdp, keep-alive
├── startwm.sh                 # XFCE session + logout watchdog
├── reconnectwm.sh             # Reconnect helper
├── skel/                      # Copied to /etc/skel in the image
│   ├── .Xclients
│   └── .config/xfce4/…/xfwm4.xml
├── README.md
└── GUIDE.md                   # This file
```

---

## Step 0 — Prerequisites

- Windows with **[wslc](https://learn.microsoft.com/en-us/windows/wsl/wsl-container)** (or Docker/Podman)
- Network to pull MCR + Fedora
- ~2 GB RAM for XFCE

---

## Step 1 — Home defaults (`skel/`)

Project `skel/` is installed as **`/etc/skel`** in the image. `useradd -m` and the Dockerfile’s `cp -a /etc/skel/. /home/azureuser/` both use it.

### `skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`

- `use_compositing = false`
- Avoids blank/glitchy frames under xorgxrdp (no good OpenGL path)

### `skel/.Xclients`

```text
startxfce4
```

Also pair with **`startwm.sh`** (watchdog) — skel alone is not enough for clean logout.

---

## Step 2 — Dockerfile stages

```dockerfile
FROM mcr.microsoft.com/azurelinux-beta/base/core:4.0

# 1) Add Fedora 43 repo (priority 50) for XFCE + xrdp
# 2) dnf install XFCE, xrdp, xorgxrdp, net tools
# 3) COPY skel/ /etc/skel/
# 4) useradd azureuser; apply skel; .xsession → startxfce4
# 5) COPY startwm.sh reconnectwm.sh; KillDisconnected=true
# 6) ENTRYPOINT docker-entrypoint.sh
```

### Package names (RHEL / Fedora / Azure Linux)

| Role | Package(s) |
|---|---|
| Package manager | `dnf` / `dnf5` (AZL 4.0) |
| RDP | `xrdp`, `xorgxrdp` |
| X server | `xorg-x11-server-Xorg`, `xorg-x11-xauth` |
| XFCE session | `xfce4-session`, `xfwm4`, `xfdesktop`, `xfce4-panel`, `xfce4-settings` |
| Terminal / FM | `xfce4-terminal`, `thunar` |
| DNS tools | `bind-utils` |
| netcat | `nmap-ncat` |
| ping | `iputils` |
| process tools | `procps-ng` |
| CA certs | `ca-certificates` |

### Critical Azure Linux fact

**Stock Azure Linux 4.0 does not ship a desktop environment or xrdp.**  
The Dockerfile adds **Fedora 43 Everything** with `priority=50` and `excludepkgs` so Azure keeps kernel/systemd/glibc/dnf ownership where possible. Fine for lab containers; not a production support matrix.

If `dnf install xrdp xfce4-session` fails:

```bash
dnf search xrdp xfce4-session xfwm4
cat /etc/yum.repos.d/fedora43-desktop.repo
```

---

## Step 3 — Session scripts

| File | Role |
|---|---|
| `docker-entrypoint.sh` | If DNS is dead, write `1.1.1.1` / `8.8.8.8`; clear X sockets; start dbus + xrdp; `sleep infinity` |
| `startwm.sh` | `XDG_SESSION_TYPE=x11`, start `startxfce4` under `dbus-run-session`, **end session when XFCE dies** (logout) |
| `reconnectwm.sh` | Best-effort `startxfce4` restart if shell died on reconnect |

**Not Wayland:** classic xrdp + xorgxrdp is **X11**.

### `startwm.sh` shape

```sh
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
dbus-run-session -- startxfce4 &
# watchdog on xfce4-session / xfwm4 …
```

---

## Step 4 — Build

```powershell
cd $env:USERPROFILE\azurelinux-rdp
wslc build -t azurelinux-xfce:rdp .
```

Docker:

```powershell
docker build -t azurelinux-xfce:rdp .
```

First build is slow (Fedora metadata + XFCE graph).

---

## Step 5 — Run

```powershell
wslc list -a
wslc remove -f azl-rdp 2>$null

wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp
```

| Flag | Meaning |
|---|---|
| `-d` | Detached |
| `--name azl-rdp` | Container name |
| `-p 13392:3389` | Host RDP → container xrdp |
| `-m 2G` | Memory limit |

Optional:

```powershell
# Persist home
wslc run -d --name azl-rdp -p 13392:3389 -m 2G `
  -v "$env:USERPROFILE\azl-rdp-home:/home/azureuser" `
  azurelinux-xfce:rdp

# Force DNS
wslc run -d --name azl-rdp -p 13392:3389 -m 2G --dns 1.1.1.1 --dns 8.8.8.8 azurelinux-xfce:rdp
```

### Port already in use?

```powershell
wslc list -a
wslc remove -f <name-using-the-port>
# or: -p 13393:3389
```

---

## Step 6 — Connect from Windows

| Field | Value |
|---|---|
| Address | `127.0.0.1:13392` |
| Username | **`azureuser`** |
| Password | **`azureuser`** |
| Session | **Xorg** (if asked) |

```powershell
mstsc /v:127.0.0.1:13392
```

### Day-to-day

```powershell
wslc stop azl-rdp
wslc start azl-rdp
```

Prefer **closing the RDP window** (disconnect). After XFCE **Log Out**, sign in again for a fresh session (the watchdog tears down a half-dead session).

---

## Step 7 — Networking & dnf inside the container

### Repos

| Repo | Role |
|---|---|
| Azure Linux base / microsoft (from image) | Core OS, preferred |
| `fedora43-desktop.repo` | XFCE, xrdp, Xorg, fonts (fill-in) |

```bash
sudo dnf makecache
sudo dnf install -y htop
```

### DNS

If resolution fails:

1. Entrypoint should rewrite resolvers when probes fail.  
2. Or run with `--dns 1.1.1.1 --dns 8.8.8.8`.  
3. Or inside:

```bash
echo -e 'nameserver 1.1.1.1\nnameserver 8.8.8.8' | sudo tee /etc/resolv.conf
sudo dnf makecache
```

### Tools (RHEL names)

| Tool | Package |
|---|---|
| `ping` | `iputils` |
| `dig` / `nslookup` / `host` | `bind-utils` |
| `wget` / `curl` | `wget`, `curl` |
| `ip` / `ss` | `iproute` |
| `ifconfig` / `netstat` | `net-tools` |
| `traceroute` | `traceroute` |
| `nc` | `nmap-ncat` |

Smoke:

```powershell
wslc exec azl-rdp bash -c "which ping dig wget; getent hosts packages.microsoft.com; dnf --version"
```

---

## Step 8 — Window manager notes (xfwm4)

Under xorgxrdp:

1. Keep **compositing off** (`xfwm4.xml` in skel).  
2. Ensure **xfwm4** is running after login.  
3. Use **Xorg** session type in the RDP client, not Wayland.

Verify while logged in:

```powershell
wslc exec azl-rdp bash -c "pgrep -a xfwm4; pgrep -a xfce4-session; pgrep -a xrdp"
```

---

## Step 9 — Rebuild after changes

```powershell
cd $env:USERPROFILE\azurelinux-rdp
wslc build -t azurelinux-xfce:rdp .
wslc remove -f azl-rdp
wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp
```

---

## Step 10 — Non-container (VM / bare dnf host)

Same package intent on a host that already has XFCE/xrdp in its repos:

```bash
sudo dnf -y update
sudo dnf -y install \
  xfce4-session xfwm4 xfdesktop xfce4-panel xfce4-settings \
  xfce4-terminal thunar \
  xrdp xorgxrdp xorg-x11-server-Xorg \
  iproute iputils bind-utils curl wget

sudo useradd -m -G wheel azureuser || true
echo 'azureuser:azureuser' | sudo chpasswd

echo 'startxfce4' | sudo tee /home/azureuser/.Xclients
sudo chmod +x /home/azureuser/.Xclients
sudo chown azureuser:azureuser /home/azureuser/.Xclients

# Optional: install the same startwm.sh / reconnectwm.sh into /etc/xrdp/
sudo systemctl enable --now xrdp
sudo firewall-cmd --permanent --add-port=3389/tcp
sudo firewall-cmd --reload
```

On **stock Azure Linux VMs**, you still need a desktop-capable repo (or package builds). The container path documents the Fedora fill-in approach.

---

## Step 11 — Publish (optional)

```powershell
# GHCR example
$env:CR_PAT = "<github classic PAT with write:packages>"
wslc login -u <github username> -p $env:CR_PAT ghcr.io
wslc tag azurelinux-xfce:rdp ghcr.io/<github username>/azurelinux-xfce-rdp:rdp
wslc push ghcr.io/<github username>/azurelinux-xfce-rdp:rdp
```

Set package **Public** if you want anonymous pulls; connect package ↔ repo in the GitHub UI.  
Dockerfile has `org.opencontainers.image.source` (edit URL to match your repo).

---

## Command cheat sheet

```powershell
# Build
cd $env:USERPROFILE\azurelinux-rdp
wslc build -t azurelinux-xfce:rdp .

# Run
wslc remove -f azl-rdp 2>$null
wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp

# Connect
mstsc /v:127.0.0.1:13392
# azureuser / azureuser

# Inspect
wslc list
wslc exec azl-rdp bash -c "pgrep -a xrdp; pgrep -a xfwm4; cat /etc/os-release"

# Logs
wslc exec azl-rdp bash -c "tail -80 /var/log/xrdp-sesman.log; tail -80 /var/log/xrdp.log"
```

---

## Troubleshooting

| Symptom | Try |
|---|---|
| Port in use | Other host port or `wslc remove -f …` |
| Connection refused | Container running? `wslc list` |
| Black screen after logout | Watchdog + `KillDisconnected`; log in again, or `pkill -9 -u azureuser` |
| Blank/compositor glitches | Confirm xfwm4 compositor off (`skel` → `xfwm4.xml`) |
| `dnf` can’t resolve | Entrypoint DNS / `--dns 1.1.1.1` |
| `No match for argument: xfce4-session` | Fedora repo not loaded or arch mismatch; check `fedora43-desktop.repo` |
| Dependency chaos after layering Fedora | Rebuild clean; tighten `excludepkgs` rather than mutate a running image |
| Red cgroup/swap warning on `wslc run` | Often harmless if container is **running** |

---

## Security

Default **`azureuser` / `azureuser`** is for **localhost demos only**.  
Do **not** publish port 3389 to the open internet with the default password.

Azure Linux 4.0 container tags may be **beta/preview** — treat as evaluation.

---

## Credits

- **Base:** [Azure Linux](https://github.com/microsoft/azurelinux) / MCR `azurelinux-beta/base/core:4.0`  
- **Desktop packages:** Fedora 43 (fill-in; not shipped by stock Azure Linux)  
- **XFCE + xrdp:** common cloud RDP practice  

Lab / education image only. Not an official Microsoft desktop product.
