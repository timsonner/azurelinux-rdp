# Azure Linux XFCE — container edition (RDP)

**Azure Linux 4.0** base + **XFCE** + **xrdp** for remote desktop from Windows. A standalone **dnf / RHEL-family** desktop container recipe you can reuse for future images.

| | |
|---|---|
| **Base** | `mcr.microsoft.com/azurelinux-beta/base/core:4.0` |
| **Desktop** | XFCE (X11) over **xrdp** |
| **Packages** | Azure core + Fedora 43 fill-in (stock AZL has no DE) |
| **Runtime** | [wslc](https://learn.microsoft.com/en-us/windows/wsl/wsl-container), Docker, or Podman |
| **Creds** | `azureuser` / `azureuser` |

Full recipe, package names, and troubleshooting: **[GUIDE.md](./GUIDE.md)**.

> XFCE is light. **~2 GB** RAM is usually enough for a lab session.

---

## Build and run

```powershell
cd $env:USERPROFILE\azurelinux-rdp
wslc build -t azurelinux-xfce:rdp .

wslc remove -f azl-rdp 2>$null
wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp
```

```bash
docker build -t azurelinux-xfce:rdp .
docker run -d --name azl-rdp -p 13392:3389 -m 2g azurelinux-xfce:rdp
```

### Connect

| Field | Value |
|---|---|
| Address | `127.0.0.1:13392` |
| Username | `azureuser` |
| Password | `azureuser` |

```powershell
mstsc /v:127.0.0.1:13392
```

Prefer **closing RDP** (disconnect). After **Log Out**, sign in again.

---

## Project layout

```text
.
├── Dockerfile
├── docker-entrypoint.sh    # DNS fallback, dbus, xrdp
├── startwm.sh              # XFCE + logout watchdog
├── reconnectwm.sh
├── skel/                   # Copied to /etc/skel (xfwm4, .Xclients)
├── GUIDE.md
└── README.md
```

---

## Architecture (short)

1. **Base:** Azure Linux 4.0 core from MCR  
2. **dnf:** XFCE, xrdp, xorgxrdp, networking tools (Fedora fill-in for DE packages)  
3. **skel:** Default user home template  
4. **User:** `azureuser` with skel applied  
5. **xrdp:** `startwm.sh` / `reconnectwm.sh`, `KillDisconnected=true`, X11 only  

---

## Security

Lab credentials only. Do not expose **3389** to the internet with `azureuser`/`azureuser`.  
Azure Linux 4.0 images may be **preview/beta**.

---

## License & credits

- Container packaging and scripts: this project  
- Base: Microsoft Azure Linux / MCR  
- Desktop RPMs: Fedora (when layered for packages stock Azure Linux does not ship)
