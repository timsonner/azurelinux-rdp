#!/bin/bash
# Container entrypoint: DNS, dbus, polkit, logind helpers, xrdp, keep-alive.
set -e

mkdir -p /run/dbus /var/run/dbus /var/run/xrdp /run/xrdp /var/log \
         /tmp/.X11-unix /run/user/1000 /run/systemd
chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true
rm -f /tmp/.X11-unix/X* /tmp/.X*-lock 2>/dev/null || true
# Stale pid files block restart ("already running")
rm -f /var/run/xrdp.pid /run/xrdp.pid \
      /var/run/xrdp-sesman.pid /run/xrdp-sesman.pid \
      /var/run/xrdp/*.pid 2>/dev/null || true

# wslc/docker often ship empty or broken resolv.conf.
if ! getent hosts packages.microsoft.com >/dev/null 2>&1 \
   && ! getent hosts dl.fedoraproject.org >/dev/null 2>&1; then
  if [ -w /etc/resolv.conf ] || [ ! -e /etc/resolv.conf ]; then
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
  fi
fi

# machine-id for systemd helpers (logind, etc.)
if [ ! -s /etc/machine-id ]; then
  if command -v systemd-machine-id-setup >/dev/null 2>&1; then
    systemd-machine-id-setup 2>/dev/null || true
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    tr -d '-' </proc/sys/kernel/random/uuid >/etc/machine-id || true
  fi
fi

if id azureuser >/dev/null 2>&1; then
  pkill -9 -u azureuser 2>/dev/null || true
  rm -f /home/azureuser/.xorgxrdp.*.log /tmp/azl-reconnect-xfce.log 2>/dev/null || true
  chown -R azureuser:azureuser /home/azureuser 2>/dev/null || true
  chown azureuser:azureuser /run/user/1000 2>/dev/null || true
  chmod 700 /run/user/1000 2>/dev/null || true
fi

# System bus — always (re)start; a stale socket without a daemon causes
# "Connection refused" and breaks session helpers / polkit.
if command -v dbus-daemon >/dev/null 2>&1; then
  if ! dbus-send --system --print-reply --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    rm -f /run/dbus/pid /run/dbus/system_bus_socket \
          /var/run/dbus/pid /var/run/dbus/system_bus_socket 2>/dev/null || true
    mkdir -p /run/dbus /var/run/dbus
    dbus-daemon --system --fork || true
  fi
fi

# polkitd — required for PolicyKit checks (XFCE session, Thunar, etc.)
if [ -x /usr/lib/polkit-1/polkitd ]; then
  if ! pgrep -x polkitd >/dev/null 2>&1; then
    /usr/lib/polkit-1/polkitd --no-debug &
    sleep 0.3
  fi
fi

# Best-effort logind (container is not systemd PID 1; may be limited).
# Still helps some D-Bus clients; polkit wheel rules cover the rest.
if [ -x /usr/lib/systemd/systemd-logind ]; then
  if ! pgrep -x systemd-logind >/dev/null 2>&1; then
    /usr/lib/systemd/systemd-logind &
    sleep 0.3
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
# Reap zombies (PID 1 with plain sleep leaves defunct children)
while true; do
  wait -n 2>/dev/null || sleep 3600
done
