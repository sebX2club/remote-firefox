FROM alpine:3.23@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63

RUN apk upgrade --no-cache && apk add --no-cache \
    bash curl dbus font-dejavu firefox novnc openbox tini x11vnc xdpyinfo xvfb \
    && addgroup -g 1000 browser \
    && adduser -D -u 1000 -G browser -h /home/browser browser \
    && mkdir -p /config/profile \
    && chown -R browser:browser /config

COPY --chmod=755 container/start.sh /usr/local/bin/start-browser
COPY --chmod=755 container/healthcheck.sh /usr/local/bin/healthcheck
ENV HOME=/home/browser DISPLAY=:99 SCREEN_SIZE=1440x900x24 START_URL=https://chatgpt.com
USER 1000:1000
EXPOSE 6080
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 CMD ["/usr/local/bin/healthcheck"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/start-browser"]
