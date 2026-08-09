#!/bin/sh
# X11 + xrdp session for XFCE (not Wayland).
# Env cleanup, dbus session, logout watchdog so reconnect is not a black screen.
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# xorgxrdp has limited GL — keep xfwm4 compositor off if possible
export XFCE_COMPOSITOR=0

# Start XFCE (do not exec — watchdog must end the xrdp session on logout)
if command -v dbus-run-session >/dev/null 2>&1; then
  dbus-run-session -- startxfce4 &
else
  startxfce4 &
fi
wmpid=$!

# Wait until session is up (or fail after ~60s)
i=0
while [ "$i" -lt 60 ]; do
  if pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1 \
     || pgrep -u "$(id -u)" -x xfwm4 >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$wmpid" 2>/dev/null; then
    wait "$wmpid"
    exit $?
  fi
  i=$((i + 1))
  sleep 1
done

# Watchdog: if the session disappears (Log Out / crash), tear down so xrdp
# does not reconnect to a black, half-dead session.
while kill -0 "$wmpid" 2>/dev/null; do
  if ! pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1 \
     && ! pgrep -u "$(id -u)" -x xfwm4 >/dev/null 2>&1; then
    sleep 2
    if ! pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1 \
       && ! pgrep -u "$(id -u)" -x xfwm4 >/dev/null 2>&1; then
      kill "$wmpid" 2>/dev/null
      pkill -u "$(id -un)" -f 'xfce4-|xfwm4|Thunar|xfsettingsd|xfdesktop' 2>/dev/null || true
      wait "$wmpid" 2>/dev/null
      exit 0
    fi
  fi
  sleep 3
done

wait "$wmpid"
exit $?
