#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ ! ${SCREEN_SIZE} =~ ^[0-9]{3,5}x[0-9]{3,5}x(16|24|32)$ ]]; then
    echo 'Invalid SCREEN_SIZE; use e.g. 1440x900x24' >&2
    exit 1
fi
mkdir -p /config/profile
if [[ ! -w /config/profile ]]; then
    echo '/config/profile must be writable by UID 1000' >&2
    exit 1
fi

pids=()
cleanup() {
    trap - EXIT TERM INT
    if ((${#pids[@]})); then
        kill -TERM "${pids[@]}" 2>/dev/null || true
        wait "${pids[@]}" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT

Xvfb "${DISPLAY}" -screen 0 "${SCREEN_SIZE}" -nolisten tcp -ac &
pids+=("$!")
ready=false
for _ in {1..100}; do
    if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
        ready=true
        break
    fi
    kill -0 "${pids[0]}" 2>/dev/null || exit 1
    sleep 0.1
done
${ready} || { echo 'Xvfb did not become ready' >&2; exit 1; }

openbox --sm-disable &
pids+=("$!")
# VNC is available only inside this container. The web port must be published
# on host loopback and reached through SSH; it deliberately has no login.
x11vnc -display "${DISPLAY}" -rfbport 5900 -localhost -forever -shared -nopw -noxdamage &
pids+=("$!")
websockify --web=/usr/share/novnc 0.0.0.0:6080 127.0.0.1:5900 &
pids+=("$!")
dbus-run-session -- firefox --no-remote --profile /config/profile "${START_URL}" &
pids+=("$!")

# Any essential process exiting restarts the complete session via systemd.
set +e
wait -n "${pids[@]}"
status=$?
set -e
((status != 0)) || status=1
exit "${status}"
