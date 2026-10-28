# Remote Firefox

Eigenes Alpine-Linux-Image mit Firefox, Xvfb, Openbox und noVNC. Gedacht für einen
Linux-Server mit Podman (z. B. Rocky Linux), bedient vom Mac über einen SSH-Tunnel.
Kein vollständiger Desktop, keine LinuxServer-Basis, keine eingebauten Zugangsdaten.

## Auf dem x86-64-Linux-Server bauen

```sh
podman build --platform linux/amd64 --format docker --pull --no-cache -t localhost/remote-firefox:latest .
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
Linux-Benutzer für den Browser. Build und Paketveröffentlichung laufen nativ auf einem x86-64-GitHub-Runner
(`ubuntu-24.04`) mit explizitem Ziel `linux/amd64`. Die Architektur des Runners
wird geprüft; es gibt keinen Mac-Build und keine QEMU-Emulation in der CI.

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

## Zwei systemweite Browser-Dienste

Unter `deploy/system/` liegen zwei unabhängige Quadlets: `remote-firefox-isa`
auf Host-Loopback-Port 6080 und `remote-firefox-sebastian` auf Port 6081.
Sie verwenden eigene benannte Profilvolumes und dasselbe lokal gebaute Image.
Diese Variante wird durch den systemweiten Podman verwaltet; die Prozesse im
Container laufen weiterhin als UID 1000. Nicht gleichzeitig mit dem rootless
Beispiel auf demselben Port betreiben.

Auf einem x86-64-Server als root (benötigt Git, Podman, Bash, Python 3, curl,
`timeout` und `flock`):

```sh
install -m 755 deploy/system/remote-firefox-build /usr/local/sbin/remote-firefox-build
install -m 644 deploy/system/*.container /etc/containers/systemd/
systemctl daemon-reload
systemctl start remote-firefox-isa.service remote-firefox-sebastian.service
systemctl status remote-firefox-isa.service remote-firefox-sebastian.service
```

Autostart wird über `WantedBy=multi-user.target` erzeugt. Ein fehlschlagender
Container-Healthcheck beendet den Container, worauf systemd ihn neu startet.
Die Volume-Namen sind `remote-firefox-isa-profile` und
`remote-firefox-sebastian-profile`.

Jeder Start und Neustart holt `main` frisch aus dem öffentlichen Repository und
baut das Image nativ für x86-64 mit aktuellen Alpine-Paketen ohne Build-Cache.
Ein Lock verhindert gleichzeitige Builds der beiden Dienste. Vor dem Umschalten
testet das Build-Skript das neue Image (Firefox-Rendering, HTTP, WebSocket/VNC,
Benutzerrechte und sauberes Stoppen). Erst dann wird `latest` ersetzt.

```sh
systemctl restart remote-firefox-isa.service
# oder unabhängig davon:
systemctl restart remote-firefox-sebastian.service
```

Während des Builds ist der neu gestartete Browser nicht erreichbar; der andere
Dienst läuft weiter. Das kann einige Minuten dauern. Auch automatische Neustarts
und ein Serverstart führen diesen Build aus. Bei Netzwerk-, Build- oder Testfehlern
wird das bisherige Image verwendet und der Fehler im Journal protokolliert.
Ohne vorhandenes Image schlägt der Start fehl. Beide Profile bleiben erhalten.
Das vorherige Image bleibt als `localhost/remote-firefox:previous` erhalten;
ungenutzte, ungetaggte Images dieses Build-Skripts werden aufgeräumt.

Die installierten Quadlets und das Build-Skript werden dabei nicht automatisch
überschrieben; aktualisiert wird der gesamte Image-Build-Kontext inklusive
Dockerfile und Container-Startskripten. Änderungen an der systemd-Integration
müssen administrativ installiert werden. `main` ist damit eine Vertrauensgrenze:
Wer dort Build-Code ändern kann, beeinflusst die auf dem Server ausgeführten
Builds und Smoke-Tests.

```sh
journalctl -u remote-firefox-isa.service -n 100 --no-pager
podman image inspect localhost/remote-firefox:latest \
  --format '{{index .Labels "org.opencontainers.image.revision"}}'
```

Optional kann ein Administrator Isa nur die Wartung ihres eigenen Dienstes
freigeben. Die Datei erlaubt feste Start-/Stop-/Restart-Befehle sowie Status und
Logs ohne Pager; sie gewährt weder eine Root-Shell noch Zugriff auf den anderen
Dienst. Vor Installation prüfen:

```sh
visudo -cf deploy/system/remote-firefox-isa.sudoers
install -o root -g root -m 440 deploy/system/remote-firefox-isa.sudoers \
  /etc/sudoers.d/remote-firefox-isa
```

Vom Client beide Ports durch denselben SSH-Tunnel weiterleiten:

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:6080:127.0.0.1:6080 \
  -L 127.0.0.1:6081:127.0.0.1:6081 benutzer@dein-server
```

Isa: <http://localhost:6080/vnc.html?autoconnect=1&resize=scale>.
Sebastian: <http://localhost:6081/vnc.html?autoconnect=1&resize=scale>.
Jede Person kann auch nur ihren eigenen Port weiterleiten. Die SSH-Anmeldung
setzt ein bereits vorhandenes, berechtigtes Konto auf dem Server voraus.

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
docker build --platform linux/amd64 --pull --no-cache -t remote-firefox:test .
bash tests/smoke.sh remote-firefox:test
# Mit Podman: CONTAINER_ENGINE=podman bash tests/smoke.sh localhost/remote-firefox:latest
```

Der CI-Smoke-Test prüft HTTP, den WebSocket-Proxy bis zur VNC-Begrüßung, Xvfb,
Firefox-Prozess, echtes Seitenrendering, Benutzerrechte und sauberes Stoppen. Ein interaktiver ChatGPT-Login
wird nicht automatisiert getestet. Basisinformationen:
[Alpine-Pakete](https://pkgs.alpinelinux.org/packages),
[Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html),
[Renovate Action](https://github.com/renovatebot/github-action).
