# Remote Firefox

Eigenes Alpine-Linux-Image mit Firefox, Xvfb, Openbox und noVNC. Gedacht für einen
Linux-Server mit Podman (z. B. Rocky Linux), bedient vom Mac über einen SSH-Tunnel.
Kein vollständiger Desktop, keine LinuxServer-Basis, keine eingebauten Zugangsdaten.

## Lokal bauen

```sh
podman build --format docker --pull --no-cache -t localhost/remote-firefox:latest .
podman run -d --name remote-firefox --shm-size=1g \
  --cap-drop=all --cap-add=sys_chroot --security-opt=no-new-privileges \
  -p 127.0.0.1:6080:6080 \
  -v remote-firefox-profile:/config localhost/remote-firefox:latest
```

Öffnen: <http://localhost:6080/vnc.html?autoconnect=1&resize=scale>.
Firefox und die Hilfsprozesse laufen unter UID/GID 1000. `SYS_CHROOT` ist für die interne Firefox-Sandbox unter dem Standard-seccomp-Profil nötig. Firefox-Sandboxing wird
nicht per Umgebungsvariable abgeschaltet. Ein leeres benanntes Podman-Volume
übernimmt beim ersten Start den vorbereiteten `/config`-Ordner samt Eigentümer.
Vorhandene Volumes müssen für UID 1000 beschreibbar sein.

## Dauerbetrieb mit rootless Podman und Quadlet

Voraussetzung: Podman mit Quadlet-Unterstützung (mindestens 4.4), systemd als
Benutzerdienst und aktivierte unprivilegierte User-Namespaces. Nutze einen eigenen
Linux-Benutzer für den Browser. Die Paketveröffentlichung liefert zunächst ein
Image für Linux/amd64; für andere Architekturen lokal bauen.

```sh
mkdir -p ~/.config/containers/systemd
cp deploy/remote-firefox.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start remote-firefox.service
systemctl --user status remote-firefox.service
journalctl --user -u remote-firefox.service -f
```

Ein Administrator aktiviert bei Bedarf den Start ohne aktive SSH-Sitzung:

```sh
sudo loginctl enable-linger DEIN_LINUX_BENUTZER
```

Quadlet erzeugt den Autostart aus `WantedBy=default.target`; die generierte Unit
wird nicht mit `systemctl enable` aktiviert. Eine vorherige systemweite oder
benutzereigene `remote-firefox.service` darf den generierten Dienst nicht überlagern.
Bei lokalem Image-Build in der Quadlet-Datei `Image=localhost/remote-firefox:latest`
setzen. Andernfalls wird `ghcr.io/sebx2club/remote-firefox:latest` verwendet.
Die GHCR-Paket-Sichtbarkeit muss nach dem ersten Publish einmal auf **Public**
gesetzt werden, damit der Server ohne Registry-Login pullen kann.

## Vom Mac zugreifen

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:6080:127.0.0.1:6080 benutzer@dein-server
```

Dann <http://localhost:6080/vnc.html?autoconnect=1&resize=scale> öffnen und Firefox
wie gewohnt benutzen. Die Verbindung zwischen Mac und Server wird durch SSH
verschlüsselt. ChatGPT-Anmeldung und Cookies bleiben im Profilvolume erhalten.

Die Weboberfläche hat **keine eigene Authentifizierung**. Port 6080 deshalb immer
an `127.0.0.1` binden und nur über SSH verwenden. Lokale Benutzer auf dem Server
können den Port ebenfalls erreichen. Der VNC-Port 5900 bleibt im Container auf
Loopback und wird nicht veröffentlicht. Keine Profilinhalte oder Cookies ins Repo
kopieren. Mikrofon, Audio und Kamera werden in dieser minimalen Lösung nicht
weitergeleitet. `SCREEN_SIZE` und `START_URL` lassen sich in der Quadlet-Datei ändern.

## Updates mit Renovate

`renovate.json` verwaltet das Alpine-Basisimage und sämtliche GitHub Actions,
einschließlich des Renovate-Workflows. Digests werden festgeschrieben, Updates
kommen als PRs, automatisches Mergen ist aus. Renovate läuft täglich und manuell
über `.github/workflows/renovate.yml`.

Einmalig in GitHub unter **Settings → Secrets and variables → Actions** das Secret
`RENOVATE_TOKEN` setzen. Dafür einen dedizierten Bot-Token verwenden, auf dieses
Repo beschränken, mit Schreibrechten für Contents, Pull requests, Issues und
Workflows sowie lesendem Metadata-Zugriff. Workflow-Schreibrechte sind nötig,
damit Renovate auch Action-Versionen aktualisieren kann. Niemals den Token committen.
Der normale `GITHUB_TOKEN` ist dafür kein geeigneter Ersatz: Änderungen damit lösen
üblicherweise keine neuen CI-Workflows aus.

Alternativ die [Mend Renovate App](https://github.com/apps/renovate) nur für dieses
Repo aktivieren und den selbst gehosteten Renovate-Workflow deaktivieren, damit
nicht zwei Instanzen gleichzeitig laufen.

Alpine-Pakete werden bewusst nicht auf einzelne Paketrevisionen festgeschrieben:
Renovate verfolgt deren Versionen hier nicht. Der Image-Workflow baut täglich mit
`--pull` und ohne Cache neu, damit aktuelle Firefox- und Systempakete aus dem
gewählten Alpine-Release eingebaut werden. Ein erfolgreich getesteter Main-Build
wird als `latest` und `sha-COMMIT` nach GHCR gepusht. Der Commit-Tag kann sich bei
einem täglichen Neubau desselben Commits ändern; für eine exakte Image-Version
den GHCR-Digest verwenden.

Ein neues Registry-Image ersetzt keinen laufenden Container. Auf dem Server:

```sh
podman pull ghcr.io/sebx2club/remote-firefox:latest
systemctl --user restart remote-firefox.service
```

Das Profil bleibt erhalten. Vor Updates kann man bei gestopptem Browser sichern:

```sh
systemctl --user stop remote-firefox.service
podman volume export remote-firefox-profile --output firefox-profile-backup.tar
systemctl --user start remote-firefox.service
```

Die Sicherung enthält private Browserdaten und gehört nicht ins öffentliche Repo.
Bei Image-Rollbacks können neuere Firefox-Profile inkompatibel sein; eine passende
Profilsicherung bereithalten.

## Checks

```sh
bash -n container/*.sh tests/*.sh
docker build --pull --no-cache -t remote-firefox:test .
bash tests/smoke.sh remote-firefox:test
# Mit Podman: CONTAINER_ENGINE=podman bash tests/smoke.sh localhost/remote-firefox:latest
```

Der CI-Smoke-Test prüft HTTP, den WebSocket-Proxy bis zur VNC-Begrüßung, Xvfb,
Firefox-Prozess, echtes Seitenrendering, Benutzerrechte und sauberes Stoppen. Ein interaktiver ChatGPT-Login
wird nicht automatisiert getestet. Basisinformationen:
[Alpine-Pakete](https://pkgs.alpinelinux.org/packages),
[Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html),
[Renovate Action](https://github.com/renovatebot/github-action).
