#!/usr/bin/env bash
set -euo pipefail
curl --fail --silent --max-time 3 http://127.0.0.1:6080/vnc.html >/dev/null
xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1
# Check the actual RFB server, not just the static noVNC page.
exec 3<>/dev/tcp/127.0.0.1/5900
IFS= read -r -t 3 greeting <&3
[[ ${greeting} == RFB* ]]
