# mailtest.sh

Bash-Script zum Testen eines SMTP-Mailservers per STARTTLS (TLS 1.2), basierend
auf `openssl s_client`. Unterstützt interaktive Eingabe und vollautomatisierten
Betrieb über CLI-Optionen bzw. Umgebungsvariablen (z.B. für CI/Cronjobs).

## Voraussetzungen

- `bash`
- `openssl` (mit `s_client`-Unterstützung)
- `base64`, `date` (Standard auf jedem Linux-System)

## Verwendung

### Interaktiv

```bash
./mailtest.sh
```

Fragt nacheinander ab:

1. Mailserver (FQDN/IP) und Port
2. Absender-Adresse und Auth-Benutzername
3. Auth-Passwort (versteckte Eingabe)
4. Empfänger-Adresse

Server, Port, Absender und Auth-Benutzername werden danach im Klartext in
`.mailtest.conf` gespeichert (Rückfrage vor dem Speichern), damit sie beim
nächsten Aufruf als Default vorgeschlagen werden. Leere Eingabe übernimmt den
angezeigten Default-Wert.

### Vollautomatisiert

```bash
MAILTEST_PASS=geheim ./mailtest.sh \
  -s mail-relay.domain.de \
  -f absender@example.com \
  -u authuser@example.com \
  -r empfaenger@example.com
```

Alle Werte lassen sich per CLI-Option oder äquivalenter Umgebungsvariable
setzen. Sind Server, Absender und Auth-Benutzername vollständig vorhanden
(CLI/ENV/gespeicherte Config), entfällt die interaktive Abfrage dafür.

## Optionen

| Option           | Beschreibung                                         |
|------------------|------------------------------------------------------|
| `-s <host>`      | Mailserver-Hostname (FQDN oder IP)                   |
| `-p <port>`      | SMTP-Port (Standard: `25`)                           |
| `-f <addr>`      | Absender-Adresse (`MAIL FROM`)                       |
| `-u <user>`      | AUTH-Benutzername                                    |
| `-r <addr>`      | Empfänger-Adresse (`RCPT TO`)                        |
| `--subject <s>`  | Betreff der Test-E-Mail                              |
| `--body <b>`     | Body der Test-E-Mail                                 |
| `--no-save`      | Server/Absender/User nicht in Config-Datei speichern |
| `-h`, `--help`   | Hilfe anzeigen                                       |

Es gibt bewusst **keine** `-P`/`--password`-Option — siehe [Passwort-Handhabung](#passwort-handhabung).

## Umgebungsvariablen

| Variable            | Entspricht Option  | Hinweis                                                   |
|---------------------|--------------------|-----------------------------------------------------------|
| `MAILTEST_SERVER`   | `-s`               |                                                           |
| `MAILTEST_PORT`     | `-p`               |                                                           |
| `MAILTEST_FROM`     | `-f`               |                                                           |
| `MAILTEST_USER`     | `-u`               |                                                           |
| `MAILTEST_PASS`     | —                  | **Einziger Weg**, das Passwort automatisiert zu übergeben |
| `MAILTEST_RCPT`     | `-r`               |                                                           |
| `MAILTEST_SUBJECT`  | `--subject`        |                                                           |
| `MAILTEST_BODY`     | `--body`           |                                                           |

ENV-Variablen werden vor der gespeicherten Config gelesen und haben Vorrang.

## Passwort-Handhabung

Das Auth-Passwort wird **niemals** in `.mailtest.conf` gespeichert. Stattdessen
gilt:

- Ist `MAILTEST_PASS` gesetzt, wird es verwendet (voll automatisierbar, z.B.
  in CI/Cron über ein Secret-Management der Umgebung).
- Ist `MAILTEST_PASS` **nicht** gesetzt, fragt das Script das Passwort
  interaktiv mit versteckter Eingabe ab — unabhängig davon, ob Server/
  Absender/User automatisiert oder aus der Config geladen wurden.
- Fehlt das Passwort am Ende beider Wege, bricht das Script mit Fehler ab.

Es gibt bewusst keine `-P`-CLI-Option für das Passwort, da Argumente in der
Prozessliste (`ps`) und Shell-History sichtbar wären.

## Config-Datei (`.mailtest.conf`)

Wird im selben Verzeichnis wie das Script abgelegt, mit `chmod 600`. Enthält
ausschließlich Server, Port, Absender und Auth-Benutzername im Klartext, als
`export MAILTEST_*=...` — die Datei ist damit direkt sourcebar, um die
ENV-Variablen in der aktuellen Shell zu setzen:

```bash
source .mailtest.conf
```

Danach sind `MAILTEST_SERVER`, `MAILTEST_PORT`, `MAILTEST_FROM` und
`MAILTEST_USER` exportiert, und das Script überspringt für diese Werte die
interaktive Abfrage automatisch (siehe oben). Die Empfänger-Adresse wird
bewusst nicht gespeichert, da sie sich pro Test üblicherweise ändert. Das
Passwort ist nie enthalten (siehe oben).

```bash
# mailtest.sh Konfiguration — Klartext, sourcebar (z.B. `source .mailtest.conf`)
export MAILTEST_SERVER="mail-relay.domain.de"
export MAILTEST_PORT="25"
export MAILTEST_FROM="absender@example.com"
export MAILTEST_USER="authuser@example.com"
```

Mit `--no-save` wird das Schreiben der Datei unterdrückt.

## SMTP-Ablauf

Das Script verbindet sich via:

```bash
openssl s_client -connect <host>:<port> -starttls smtp -crlf -tls1_2
```

und führt anschließend über den TLS-Kanal folgende SMTP-Sequenz aus:

```bash
EHLO <hostname>
AUTH LOGIN
<base64 Benutzername>
<base64 Passwort>
MAIL FROM:<absender>
RCPT TO:<empfänger>
DATA
... Header + Body ...
.
QUIT
```

## Exit-Codes

| Code | Bedeutung                                                     |
|------|---------------------------------------------------------------|
| `0`  | E-Mail erfolgreich angenommen                                 |
| `1`  | Ungültige/fehlende Eingabe (z.B. Passwort leer)               |
| `2`  | SMTP-Fehler (Auth fehlgeschlagen, Empfänger abgelehnt)        |
| `3`  | Verbindungs-/TLS-Fehler (STARTTLS-Aushandlung fehlgeschlagen) |
| `4`  | Sendestatus unklar — Ausgabe manuell prüfen                   |

## Beispiele

Test mit expliziten Werten, Passwort aus ENV, ohne Config zu speichern:

```bash
MAILTEST_PASS='S3cr3t!' ./mailtest.sh \
  -s mail-relay.domain.de \
  -f monitoring@example.com \
  -u svc-monitoring \
  -r admin@example.com \
  --subject "SMTP-Check $(date +%F)" \
  --no-save
```

Erster interaktiver Lauf (speichert Server/Absender/User für später):

```bash
./mailtest.sh
```

Folgelauf mit gespeicherter Config, nur Passwort und Empfänger nötig:

```bash
MAILTEST_PASS='S3cr3t!' ./mailtest.sh -r andere-adresse@example.com
```
