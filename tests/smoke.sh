#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:-remote-firefox:test}
engine=${CONTAINER_ENGINE:-docker}
name="remote-firefox-test-${RANDOM}"
cleanup() {
    status=$?
    if ((status != 0)); then "$engine" logs "$name" || true; fi
    "$engine" rm -fv "$name" >/dev/null || true
    return "$status"
}
trap cleanup EXIT
"$engine" run -d --name "$name" --shm-size=1g --cap-drop=ALL --cap-add=SYS_CHROOT \
    --security-opt=no-new-privileges \
    -e START_URL=about:blank -p 127.0.0.1::6080 "$image"
healthy=false
for _ in {1..90}; do
    state=$("$engine" inspect --format '{{.State.Health.Status}}' "$name")
    if [[ $state == healthy ]]; then healthy=true; break; fi
    [[ $("$engine" inspect --format '{{.State.Running}}' "$name") == true ]] || exit 1
    sleep 2
done
$healthy || { echo 'Container failed healthcheck' >&2; exit 1; }
[[ $("$engine" exec "$name" id -u) == 1000 ]]
"$engine" exec "$name" pgrep -f '/usr/lib/firefox/firefox'
"$engine" exec "$name" test -d /config/profile
# Render real page content in a separate profile with the same security policy.
"$engine" exec "$name" sh -c '
  mkdir -p /tmp/render-profile
  timeout 35 firefox --headless --no-remote --profile /tmp/render-profile \
    --screenshot /tmp/render.png \
    "data:text/html,<html><body style=background:lime>Firefox rendering test</body></html>"
  test -s /tmp/render.png
'
if "$engine" logs "$name" 2>&1 | grep -q 'Sandbox: chroot: EPERM'; then
    echo 'Firefox sandbox failed' >&2
    exit 1
fi
port=$("$engine" port "$name" 6080/tcp)
curl --fail --silent "http://$port/vnc.html" >/dev/null
# Exercise the websocket proxy as well as the HTTP page and the VNC backend.
python3 - "$port" <<'PY'
import socket, sys
host, port = sys.argv[1].rsplit(':', 1)
with socket.create_connection((host, int(port)), timeout=5) as connection:
    connection.sendall((
        'GET /websockify HTTP/1.1\r\n'
        f'Host: {host}:{port}\r\n'
        'Upgrade: websocket\r\nConnection: Upgrade\r\n'
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n'
    ).encode())
    reply = b''
    while b'\r\n\r\n' not in reply:
        part = connection.recv(4096)
        assert part, 'WebSocket connection closed during handshake'
        reply += part
    assert b' 101 ' in reply.split(b'\r\n', 1)[0], reply
    payload = reply.split(b'\r\n\r\n', 1)[1]
    while b'RFB ' not in payload:
        part = connection.recv(4096)
        assert part, 'No RFB greeting through WebSocket'
        payload += part
PY
"$engine" stop -t 30 "$name" >/dev/null
[[ $("$engine" inspect --format '{{.State.ExitCode}}' "$name") == 0 ]]
echo 'Smoke test passed'
