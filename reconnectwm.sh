#!/bin/sh
# Called by xrdp when a client reconnects to an existing session.
# Recover from "Log Out" / crashed shell leaving a black screen.

if pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1 \
   || pgrep -u "$(id -u)" -x xfwm4 >/dev/null 2>&1; then
  exit 0
fi

export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

pkill -u "$(id -un)" -f 'xfce4-|xfwm4|Thunar|xfsettingsd|xfdesktop|startxfce4' 2>/dev/null || true
sleep 1

if command -v dbus-run-session >/dev/null 2>&1; then
  nohup dbus-run-session -- startxfce4 >/tmp/azl-reconnect-xfce.log 2>&1 &
else
  nohup startxfce4 >/tmp/azl-reconnect-xfce.log 2>&1 &
fi
exit 0
