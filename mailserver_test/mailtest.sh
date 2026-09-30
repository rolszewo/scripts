#!/usr/bin/env bash
# mailtest.sh — SMTP-Test via openssl s_client mit STARTTLS
# Unterstützt interaktiven Modus und vollautomatischen Modus via Optionen.
#
# NUTZUNG (interaktiv):
#   ./mailtest.sh
#
# NUTZUNG (automatisiert):
#   MAILTEST_PASS=geheim ./mailtest.sh -s smtp.example.com -f sender@example.com \
#       -u authuser@example.com -r empfaenger@example.com
#
# CONFIG-DATEI:
#   Server/Absender/User werden im Klartext in .mailtest.conf gespeichert
#   (chmod 600), als "export MAILTEST_*=..." — die Datei ist damit direkt
#   sourcebar (z.B. `source .mailtest.conf`), um die ENV-Variablen z.B. in
#   einer Shell oder einem CI-Job zu exportieren. Das PASSWORT wird NIEMALS
#   in der Config-Datei abgelegt. Es muss immer per MAILTEST_PASS ENV-Variable
#   gesetzt werden, sonst wird interaktiv danach gefragt.
#   Bereits gesetzte ENV-Variablen werden NIE erneut interaktiv abgefragt.
#
# OPTIONEN:
#   -s <host>       Mailserver-Hostname (FQDN oder IP)
#   -p <port>       SMTP-Port (Standard: 25)
#   -f <addr>       Absender-Adresse (MAIL FROM)
#   -u <user>       AUTH-Benutzername
#   -r <addr>       Empfänger-Adresse (RCPT TO)
#   --subject <s>   Betreff der Test-E-Mail
#   --body <b>      Body der Test-E-Mail
#   --no-save       Server/Absender/User NICHT in Config-Datei speichern
#   -h, --help      Diese Hilfe anzeigen
#
# ENV-VARIABLEN (werden ZUERST gelesen, überschreiben gespeicherte Config):
#   MAILTEST_SERVER, MAILTEST_PORT, MAILTEST_FROM, MAILTEST_USER
#   MAILTEST_PASS (einziger Weg für automatisiertes Passwort — siehe CONFIG-DATEI oben)
#   MAILTEST_RCPT, MAILTEST_SUBJECT, MAILTEST_BODY

set -euo pipefail

# ─── Konfiguration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.mailtest.conf"
DEFAULT_PORT=25
DEFAULT_SUBJECT="SMTP Mailtest von mailtest.sh"
DEFAULT_BODY="Dies ist eine automatisch generierte Test-E-Mail.\nSent: $(date -u '+%Y-%m-%d %H:%M:%S UTC')\nScript: mailtest.sh"

# Farben (deaktiviert wenn kein TTY)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

# ─── Hilfsfunktionen ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

b64e() { echo -n "$1" | base64; }

usage() {
    sed -n '/^# NUTZUNG/,/^[^#]/{ /^#/{ s/^# \{0,2\}//; p }; }' "${BASH_SOURCE[0]}" | head -n -1
    exit 0
}

# ─── Config laden/speichern ────────────────────────────────────────────────────
load_config() {
    [[ -f "${CONFIG_FILE}" ]] || return 0
    local line key val
    while IFS= read -r line; do
        [[ "${line}" =~ ^# ]] && continue
        [[ -z "${line}" ]] && continue
        line="${line#export }"
        key="${line%%=*}"
        val="${line#*=}"
        # Anführungszeichen entfernen (Datei ist sourcebar und quotet Werte)
        val="${val%\"}"; val="${val#\"}"
        case "${key}" in
            MAILTEST_SERVER) [[ -z "${OPT_SERVER:-}" ]] && CFG_SERVER="${val}"; true ;;
            MAILTEST_PORT)   [[ -z "${OPT_PORT:-}" ]]   && CFG_PORT="${val}";   true ;;
            MAILTEST_FROM)   [[ -z "${OPT_FROM:-}" ]]   && CFG_FROM="${val}";   true ;;
            MAILTEST_USER)   [[ -z "${OPT_USER:-}" ]]   && CFG_USER="${val}";   true ;;
        esac
    done < "${CONFIG_FILE}"
}

save_config() {
    [[ "${NO_SAVE}" == "1" ]] && return 0
    # Passwort wird bewusst NICHT gespeichert, auch nicht codiert.
    # Format ist sourcebar: `source .mailtest.conf` exportiert die ENV-Variablen.
    cat > "${CONFIG_FILE}" <<EOF
# mailtest.sh Konfiguration — Klartext, sourcebar (z.B. \`source .mailtest.conf\`)
# Erzeugt: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Bearbeite diese Datei NICHT manuell — sie wird vom Script verwaltet.
# Passwort wird HIER NICHT gespeichert (siehe MAILTEST_PASS ENV-Variable).
export MAILTEST_SERVER="${MAILSERVER}"
export MAILTEST_PORT="${SMTP_PORT}"
export MAILTEST_FROM="${FROM_ADDR}"
export MAILTEST_USER="${AUTH_USER}"
EOF
    chmod 600 "${CONFIG_FILE}"
    success "Server/Absender/User gespeichert: ${CONFIG_FILE} (chmod 600, sourcebar) — Passwort NICHT gespeichert."
}

# ─── Argument-Parsing ──────────────────────────────────────────────────────────
OPT_SERVER="${MAILTEST_SERVER:-}"
OPT_PORT="${MAILTEST_PORT:-}"
OPT_FROM="${MAILTEST_FROM:-}"
OPT_USER="${MAILTEST_USER:-}"
# Passwort ausschließlich via ENV-Variable — keine CLI-Option (würde in
# ps/history sichtbar sein und ist damit ein Sicherheitsrisiko).
OPT_PASS="${MAILTEST_PASS:-}"
OPT_RCPT="${MAILTEST_RCPT:-}"
OPT_SUBJECT="${MAILTEST_SUBJECT:-}"
OPT_BODY="${MAILTEST_BODY:-}"
NO_SAVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s)           OPT_SERVER="$2";   shift 2 ;;
        -p)           OPT_PORT="$2";     shift 2 ;;
        -f)           OPT_FROM="$2";     shift 2 ;;
        -u)           OPT_USER="$2";     shift 2 ;;
        -r)           OPT_RCPT="$2";     shift 2 ;;
        --subject)    OPT_SUBJECT="$2";  shift 2 ;;
        --body)       OPT_BODY="$2";     shift 2 ;;
        --no-save)    NO_SAVE=1;         shift   ;;
        -h|--help)    usage ;;
        *) die "Unbekannte Option: $1 (--help für Hilfe)" ;;
    esac
done

# ─── Abhängigkeiten prüfen ─────────────────────────────────────────────────────
for cmd in openssl base64 date; do
    command -v "${cmd}" &>/dev/null || die "Benötigt: ${cmd} (nicht gefunden)"
done

# ─── Config-Datei laden (gespeicherte Defaults) ────────────────────────────────
CFG_SERVER=""; CFG_PORT=""; CFG_FROM=""; CFG_USER=""
load_config

# ─── Interaktiver Prompt ───────────────────────────────────────────────────────
prompt_default() {
    # prompt_default <Frage> <Variablenname> <Default-Wert> [noecho]
    local question="$1" varname="$2" default="$3" noecho="${4:-}"
    local prompt_str="${BOLD}${question}${RESET}"
    [[ -n "${default}" ]] && prompt_str+=" ${CYAN}[${default}]${RESET}"
    prompt_str+=": "

    local input
    if [[ "${noecho}" == "noecho" ]]; then
        echo -ne "${prompt_str}"
        IFS= read -rs input
        echo  # Zeilenumbruch nach versteckter Eingabe
    else
        echo -ne "${prompt_str}"
        IFS= read -r input
    fi

    # Leer → Default übernehmen
    [[ -z "${input}" && -n "${default}" ]] && input="${default}"
    printf -v "${varname}" '%s' "${input}"
}

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e " ${BOLD}mailtest.sh${RESET} — SMTP-Test mit STARTTLS (TLS 1.2)"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# Server/Absender/User nur abfragen wenn nicht vollständig via CLI/ENV/Config vorhanden.
# Das Passwort ist HIER bewusst ausgeklammert — es wird immer separat behandelt
# (siehe unten), egal ob der Rest automatisiert läuft oder nicht.
if [[ -n "${OPT_SERVER}" && -n "${OPT_FROM}" && -n "${OPT_USER}" ]]; then
    MAILSERVER="${OPT_SERVER}"
    SMTP_PORT="${OPT_PORT:-${CFG_PORT:-${DEFAULT_PORT}}}"
    FROM_ADDR="${OPT_FROM}"
    AUTH_USER="${OPT_USER}"
    info "Server/Absender/User aus CLI/ENV übernommen — überspringe interaktive Eingabe dafür."
else
    # Interaktiver Modus
    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Gespeicherte Konfiguration gefunden: ${CONFIG_FILE}"
        info "Leere Eingabe übernimmt den gespeicherten Wert (in eckigen Klammern)."
        echo
    fi

    echo -e "${BOLD}── Server-Konfiguration ──────────────────────────────${RESET}"
    prompt_default "Mailserver (FQDN/IP)" MAILSERVER "${OPT_SERVER:-${CFG_SERVER:-mail-relay.domain.de}}"
    prompt_default "SMTP-Port            " SMTP_PORT  "${OPT_PORT:-${CFG_PORT:-${DEFAULT_PORT}}}"

    echo -e "\n${BOLD}── Absender & Authentifizierung ──────────────────────${RESET}"
    prompt_default "Absender-Adresse     " FROM_ADDR  "${OPT_FROM:-${CFG_FROM:-}}"
    prompt_default "Auth-Benutzername    " AUTH_USER  "${OPT_USER:-${CFG_USER:-}}"

    # Validierung der Pflichtfelder
    [[ -z "${MAILSERVER}" ]] && die "Mailserver darf nicht leer sein."
    [[ -z "${FROM_ADDR}" ]]  && die "Absender-Adresse darf nicht leer sein."
    [[ -z "${AUTH_USER}" ]]  && die "Auth-Benutzername darf nicht leer sein."

    # Server/Absender/User speichern? (Passwort wird NIE gespeichert)
    if [[ "${NO_SAVE}" == "0" ]]; then
        echo
        echo -ne "${BOLD}Server/Absender/User in ${CONFIG_FILE} speichern?${RESET} ${CYAN}[J/n]${RESET}: "
        read -r save_ans
        [[ "${save_ans,,}" == "n" ]] && NO_SAVE=1
    fi
    save_config
fi

# Passwort: ausschließlich via MAILTEST_PASS ENV-Variable, sonst interaktive Abfrage.
# Das gilt unabhängig davon, ob Server/Absender/User automatisiert wurden.
echo -e "\n${BOLD}── Authentifizierung ──────────────────────────────────${RESET}"
if [[ -n "${OPT_PASS}" ]]; then
    AUTH_PASS="${OPT_PASS}"
    info "Passwort aus MAILTEST_PASS ENV-Variable übernommen."
else
    echo -ne "${BOLD}Auth-Passwort${RESET}: "
    IFS= read -rs AUTH_PASS
    echo
fi
[[ -z "${AUTH_PASS}" ]] && die "Passwort darf nicht leer sein (MAILTEST_PASS setzen oder interaktiv eingeben)."

# Empfänger abfragen (bewusst NICHT in Config gespeichert — ändert sich häufig)
echo -e "\n${BOLD}── Empfänger ─────────────────────────────────────────${RESET}"
if [[ -n "${OPT_RCPT}" ]]; then
    RCPT_ADDR="${OPT_RCPT}"
    info "Empfänger: ${RCPT_ADDR}"
else
    prompt_default "Empfänger-Adresse" RCPT_ADDR "${OPT_RCPT:-}"
    [[ -z "${RCPT_ADDR}" ]] && die "Empfänger-Adresse darf nicht leer sein."
fi

# Betreff und Body
SUBJECT="${OPT_SUBJECT:-${DEFAULT_SUBJECT}}"
BODY="${OPT_BODY:-${DEFAULT_BODY}}"

# ─── SMTP-Session aufbauen ─────────────────────────────────────────────────────
AUTH_USER_B64="$(b64e "${AUTH_USER}")"
AUTH_PASS_B64="$(b64e "${AUTH_PASS}")"
MESSAGE_ID="<mailtest-$(date +%s)-$$@${MAILSERVER}>"
DATE_STR="$(date -R)"

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
info "Verbinde mit ${MAILSERVER}:${SMTP_PORT} via STARTTLS (TLS 1.2) ..."
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# SMTP-Kommandos; openssl -crlf konvertiert \n selbst zu \r\n beim Senden —
# hier daher NUR \n verwenden, sonst entsteht \r\r\n und der Server lehnt Zeilen ab.
SMTP_COMMANDS=$(printf '%s\n' \
    "EHLO $(hostname -f 2>/dev/null || hostname)" \
    "AUTH LOGIN" \
    "${AUTH_USER_B64}" \
    "${AUTH_PASS_B64}" \
    "MAIL FROM:<${FROM_ADDR}>" \
    "RCPT TO:<${RCPT_ADDR}>" \
    "DATA" \
    "Date: ${DATE_STR}" \
    "From: ${FROM_ADDR}" \
    "To: ${RCPT_ADDR}" \
    "Message-ID: ${MESSAGE_ID}" \
    "Subject: ${SUBJECT}" \
    "MIME-Version: 1.0" \
    "Content-Type: text/plain; charset=UTF-8" \
    "" \
    "$(echo -e "${BODY}")" \
    "" \
    "." \
    "QUIT" \
)

# Ausgabe-Log Tempfile
LOGFILE="$(mktemp /tmp/mailtest_XXXXXX.log)"
trap 'rm -f "${LOGFILE}"' EXIT

# openssl startet, wir übergeben alle SMTP-Kommandos via stdin.
# Der Server sendet Prompts/Responses – openssl gibt sie aus und schickt unsere Zeilen.
set +e
{
    # Kurzes Warten auf Server-Greeting (220-Banner)
    sleep 1
    echo -e "${SMTP_COMMANDS}"
} | openssl s_client \
        -connect "${MAILSERVER}:${SMTP_PORT}" \
        -starttls smtp \
        -crlf \
        -tls1_2 \
        -quiet \
        2>&1 | tee "${LOGFILE}"

OPENSSL_EXIT=${PIPESTATUS[1]}
set -e

# ─── Ergebnis auswerten ────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# Fehler-Codes MÜSSEN zuerst geprüft werden: EHLO/STARTTLS liefern bereits eigene
# 250-Antworten, daher würde ein reiner "250 vorhanden"-Check eine fehlgeschlagene
# Auth (535) oder Zustellung (550) fälschlich als Erfolg werten.
if grep -qE '^(535|534)' "${LOGFILE}"; then
    SMTP_ERR=$(grep -E '^(535|534)' "${LOGFILE}" | head -1)
    error "SMTP-Fehler: ${SMTP_ERR}"
    error "Authentifizierung fehlgeschlagen — Benutzername/Passwort prüfen."
    exit 2
elif grep -qE '^530' "${LOGFILE}"; then
    SMTP_ERR=$(grep -E '^530' "${LOGFILE}" | head -1)
    error "SMTP-Fehler: ${SMTP_ERR}"
    error "Authentifizierung erforderlich — Server verlangt AUTH vor weiteren Befehlen."
    exit 2
elif grep -qE '^(550|554)' "${LOGFILE}"; then
    SMTP_ERR=$(grep -E '^(550|554)' "${LOGFILE}" | head -1)
    error "SMTP-Fehler: ${SMTP_ERR}"
    error "Zustellung abgelehnt — Empfänger oder Absender abgelehnt."
    exit 2
elif grep -qE '^354' "${LOGFILE}" && awk '/^354/{f=1;next} f&&/^250/{found=1} END{exit !found}' "${LOGFILE}"; then
    success "E-Mail wurde vom Server angenommen!"
    echo -e "  ${CYAN}Von:${RESET}       ${FROM_ADDR}"
    echo -e "  ${CYAN}An:${RESET}        ${RCPT_ADDR}"
    echo -e "  ${CYAN}Server:${RESET}    ${MAILSERVER}:${SMTP_PORT}"
    echo -e "  ${CYAN}Message-ID:${RESET} ${MESSAGE_ID}"
elif [[ "${OPENSSL_EXIT}" -ne 0 ]]; then
    error "openssl Verbindungsfehler (Exit ${OPENSSL_EXIT})."
    error "TLS-Verbindung oder STARTTLS-Aushandlung fehlgeschlagen."
    error "Server: ${MAILSERVER}:${SMTP_PORT}"
    exit 3
else
    warn "Konnte Sendestatus nicht eindeutig bestimmen. SMTP-Ausgabe oben prüfen."
    exit 4
fi

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
