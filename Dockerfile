# Azure Linux 4.0 + XFCE + xrdp (container edition)
#
# Build:  wslc build -t azurelinux-xfce:rdp .
#         docker build -t azurelinux-xfce:rdp .
# Run:    wslc run -d --name azl-rdp -p 13392:3389 -m 2G azurelinux-xfce:rdp
#
# Stock Azure Linux has no desktop stack. XFCE / xrdp come from Fedora 43
# (Azure Linux 4.0 is Fedora-lineage compatible). See GUIDE.md.

FROM mcr.microsoft.com/azurelinux-beta/base/core:4.0

LABEL org.opencontainers.image.title="Azure Linux XFCE (RDP)"
LABEL org.opencontainers.image.description="Azure Linux 4.0 base + XFCE + xrdp — container edition (dnf/RHEL-family pattern)"
LABEL org.opencontainers.image.source="https://github.com/timsonner/azurelinux-xfce-rdp"
LABEL org.opencontainers.image.licenses="MIT"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- Repos: Azure first, Fedora 43 for desktop/RDP packages -----------------
# priority: lower number wins on dnf (Azure base stays preferred for core).
RUN set -eux; \
    tdnf install -y ca-certificates curl dnf || \
    dnf install -y ca-certificates curl || true; \
    mkdir -p /etc/yum.repos.d; \
    cat > /etc/yum.repos.d/fedora43-desktop.repo <<'EOF'
[fedora43-desktop]
name=Fedora 43 Everything (desktop fill-in for Azure Linux 4.0)
baseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Everything/x86_64/os/
enabled=1
gpgcheck=0
priority=50
# Keep Azure owning core userland where possible
excludepkgs=kernel*,systemd*,glibc*,bash,coreutils*,util-linux*,shadow-utils*,sudo,openssh*,NetworkManager*,dnf*,libdnf*,rpm*,cryptsetup*,device-mapper*,lvm2*,selinux*,audit*,polkit*,dbus,dbus-broker,dbus-daemon,dbus-libs,dbus-common,dbus-tools

[fedora43-updates-desktop]
name=Fedora 43 Updates (desktop fill-in)
baseurl=https://dl.fedoraproject.org/pub/fedora/linux/updates/43/Everything/x86_64/
enabled=1
gpgcheck=0
priority=50
excludepkgs=kernel*,systemd*,glibc*,bash,coreutils*,util-linux*,shadow-utils*,sudo,openssh*,NetworkManager*,dnf*,libdnf*,rpm*,cryptsetup*,device-mapper*,lvm2*,selinux*,audit*,polkit*,dbus,dbus-broker,dbus-daemon,dbus-libs,dbus-common,dbus-tools
EOF

# Prefer dnf5 if present (Azure Linux 4.0); fall back to dnf/tdnf.
# Package names are Fedora/RHEL-style.
RUN set -eux; \
    PM=""; \
    if command -v dnf5 >/dev/null 2>&1; then PM=dnf5; \
    elif command -v dnf >/dev/null 2>&1; then PM=dnf; \
    elif command -v tdnf >/dev/null 2>&1; then PM=tdnf; \
    else echo "No dnf/tdnf found" >&2; exit 1; fi; \
    $PM -y makecache || true; \
    $PM -y install \
        sudo passwd shadow-utils \
        ca-certificates \
        dbus dbus-daemon dbus-tools \
        xrdp xorgxrdp \
        xorg-x11-server-Xorg xorg-x11-xauth xorg-x11-xinit \
        xorg-x11-drivers xorg-x11-utils \
        xfce4-session xfce4-panel xfce4-settings xfce4-terminal \
        xfce4-appfinder xfdesktop xfwm4 thunar \
        xfce4-whiskermenu-plugin mousepad \
        dejavu-sans-fonts google-noto-sans-fonts google-noto-emoji-fonts \
        iproute iputils net-tools curl wget \
        traceroute bind-utils nmap-ncat procps-ng \
        which hostname findutils tar gzip \
    || $PM -y install \
        sudo passwd shadow-utils ca-certificates \
        dbus \
        xrdp xorgxrdp \
        xorg-x11-server-Xorg xorg-x11-xauth \
        xfce4-session xfce4-panel xfce4-settings xfce4-terminal \
        xfce4-appfinder xfdesktop xfwm4 thunar \
        iproute iputils curl wget bind-utils procps-ng; \
    $PM clean all || true; \
    rm -rf /var/cache/dnf /var/cache/tdnf /var/cache/yum

# Default home template (xfwm4 compositor off, .Xclients). See GUIDE.md.
COPY skel/ /etc/skel/

# System overlay: polkit lab rules, disable broken xfce-polkit agent autostart.
COPY overlay/ /

# Default RDP user
RUN set -eux; \
    groupadd -f wheel; \
    useradd -m -s /bin/bash -G wheel azureuser; \
    echo 'azureuser:azureuser' | chpasswd; \
    echo 'azureuser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/azureuser; \
    chmod 440 /etc/sudoers.d/azureuser; \
    cp -a /etc/skel/. /home/azureuser/ 2>/dev/null || true; \
    printf '%s\n' '#!/bin/sh' 'exec startxfce4' > /home/azureuser/.xsession; \
    printf '%s\n' 'startxfce4' > /home/azureuser/.Xclients; \
    chown -R azureuser:azureuser /home/azureuser; \
    chmod +x /home/azureuser/.xsession /home/azureuser/.Xclients

# xrdp is X11 (not Wayland). Session scripts end cleanly after XFCE logout.
COPY startwm.sh /etc/xrdp/startwm.sh
COPY reconnectwm.sh /etc/xrdp/reconnectwm.sh
RUN set -eux; \
    chmod +x /etc/xrdp/startwm.sh /etc/xrdp/reconnectwm.sh; \
    # Fedora xrdp uses DefaultWindowManager=startwm-bash.sh which sources
    # /usr/libexec/xrdp/startwm.sh — not /etc/xrdp/startwm.sh alone.
    mkdir -p /usr/libexec/xrdp; \
    cp -a /etc/xrdp/startwm.sh /usr/libexec/xrdp/startwm.sh; \
    chmod +x /usr/libexec/xrdp/startwm.sh; \
    if [ -f /etc/xrdp/reconnectwm.sh ]; then \
      cp -a /etc/xrdp/reconnectwm.sh /usr/libexec/xrdp/reconnectwm.sh 2>/dev/null || true; \
    fi; \
    mkdir -p /etc/X11; \
    printf '%s\n' 'allowed_users=anybody' 'needs_root_rights=yes' > /etc/X11/Xwrapper.config; \
    # Force RFX only. Fedora pulls noopenh264 (stub SONAME) so H.264 leaves
    # "encoder is nil" and Windows mstsc shows a black screen while XFCE runs.
    printf '%s\n' \
      '[codec]' \
      '# RFX only — H.264 needs real x264/openh264 (not the noopenh264 stub)' \
      'order = [ "RFX" ]' \
      > /etc/xrdp/gfx.toml; \
    # Prefer solid bitmap path over flaky 32bpp+GFX on some clients
    if [ -f /etc/xrdp/xrdp.ini ]; then \
      sed -i 's/^max_bpp=.*/max_bpp=24/' /etc/xrdp/xrdp.ini; \
      sed -i 's/^#max_bpp=.*/max_bpp=24/' /etc/xrdp/xrdp.ini; \
    fi; \
    if [ -f /etc/xrdp/sesman.ini ]; then \
      sed -i 's/^KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini; \
      sed -i 's/^DisconnectedTimeLimit=.*/DisconnectedTimeLimit=0/' /etc/xrdp/sesman.ini; \
      grep -q '^KillDisconnected=' /etc/xrdp/sesman.ini || \
        printf '\n[Sessions]\nKillDisconnected=true\nDisconnectedTimeLimit=0\n' >> /etc/xrdp/sesman.ini; \
    fi

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 3389

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD bash -c 'ss -lntp 2>/dev/null | grep -q 3389 || exit 1'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
