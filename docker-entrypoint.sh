#!/bin/bash
# Container entrypoint: DNS fallback, clean X/xrdp state, dbus, xrdp, keep-alive.
set -e

mkdir -p /run/dbus /var/run/xrdp /var/log /tmp/.X11-unix /run/user/1000
chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true
rm -f /tmp/.X11-unix/X* /tmp/.X*-lock 2>/dev/null || true
rm -f /run/dbus/pid /var/run/xrdp/*.pid /var/run/xrdp-sesman.pid 2>/dev/null || true

# wslc/docker often ship empty or broken resolv.conf.
# Probe something the image actually needs (Azure or Fedora mirror).
if ! getent hosts packages.microsoft.com >/dev/null 2>&1 \
   && ! getent hosts dl.fedoraproject.org >/dev/null 2>&1; then
  if [ -w /etc/resolv.conf ] || [ ! -e /etc/resolv.conf ]; then
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
  fi
fi

if id azureuser >/dev/null 2>&1; then
  pkill -9 -u azureuser 2>/dev/null || true
  rm -f /home/azureuser/.xorgxrdp.*.log /tmp/azl-reconnect-xfce.log 2>/dev/null || true
  chown -R azureuser:azureuser /home/azureuser 2>/dev/null || true
  chown azureuser:azureuser /run/user/1000 2>/dev/null || true
  chmod 700 /run/user/1000 2>/dev/null || true
fi

# System bus (session helpers, some DE bits)
if [ ! -S /run/dbus/system_bus_socket ]; then
  if command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork || true
  fi
fi

# xrdp stack
pgrep -x xrdp-sesman >/dev/null 2>&1 || xrdp-sesman || true
pgrep -x xrdp >/dev/null 2>&1 || xrdp || true

echo "Azure Linux XFCE (container) — RDP on port 3389"
echo "  user: azureuser"
echo "  pass: azureuser"
echo "  base: mcr.microsoft.com/azurelinux-beta/base/core:4.0"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec sleep infinity
