# AGENTS.md

## Project

Single-file bash tool (`mailtest.sh`) that tests an SMTP mailserver via
`openssl s_client` with STARTTLS (TLS 1.2). No build system, no package
manager, no tests directory. Documentation is in German (`README.md`,
inline script comments).

## Files

- `mailtest.sh` — the entire tool. Interactive + fully-automated modes via
  CLI options / `MAILTEST_*` env vars.
- `.mailtest.conf` — generated, sourceable config (`export MAILTEST_*=...`),
  `chmod 600`. Holds server/port/from/user only. **Never** holds the
  password — that is only ever supplied via `MAILTEST_PASS` env var.
- `README.md` — user-facing docs (German). Keep in sync with script
  behavior/options/env-vars when changing `mailtest.sh`.

## Conventions

- `set -euo pipefail` is active — any `[[ cond ]] && stmt` used as the last
  statement in a function/loop body is a bug trap: if `cond` is false, the
  `&&` expression's exit code is non-zero and `set -e` kills the whole
  script silently. Use `if/then`, or append `; true` after such statements.
- Password handling is intentionally restrictive: no `-P`/`--password` CLI
  flag exists (would leak via `ps`/shell history). Only `MAILTEST_PASS` env
  var or an interactive hidden prompt. Do not add a CLI flag for it.
- Comments/docs are German; match that when editing existing sections.
- SMTP commands piped to `openssl s_client -crlf` must use `\n` only, never
  `\r\n` — openssl converts `\n`→`\r\n` itself; doubling it breaks the
  server's line parsing.
- Config file keys are `MAILTEST_SERVER`, `MAILTEST_PORT`, `MAILTEST_FROM`,
  `MAILTEST_USER` (exported, quoted). `RCPT`/`SUBJECT`/`BODY` are
  deliberately never persisted (change per-run).

## Verification

No test suite. After editing `mailtest.sh`:
1. `bash -n mailtest.sh` (syntax check)
2. Exercise both interactive and fully-automated (env-var) code paths,
   especially `load_config`/`save_config` and any `set -e`-sensitive
   conditionals.
3. Real run against the actual configured mail relay is the only way to
   confirm SMTP-flow correctness (see `.mailtest.conf` for the known-good
   test server this repo targets).

## Constraints

- Never commit `.mailtest.conf` or any file containing `MAILTEST_PASS`.
- Never add a way to pass the password via CLI argument.
- Keep `README.md` and the script's `usage()`-generated help (parsed from
  the top-of-file comment block) consistent with actual behavior.
