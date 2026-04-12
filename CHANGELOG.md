# Changelog

All notable changes to this project will be documented in this file.

---

## [1.0.0] – 2026-04-12

Initial public release.

### Features
- **Service mode** — persistent TrueConf connection with an async message
  queue; picks up Zabbix alert tasks within ~1 second.  Recommended for
  production where alert bursts are expected.
- **Queue mode** — Zabbix alertscript writes a task file to `queue/` and
  exits immediately; the running service delivers it asynchronously.
- **Direct mode** — one-shot connect / send / disconnect fallback when the
  service is not installed or for infrequent alerts.
- Email → TrueConf ID conversion via configurable domain mapping in
  `config.toml`.
- Atomic queue writes (write-to-tmp-then-rename) — service never reads a
  partially written task file.
- Linux systemd service installer (`install.sh`) and uninstaller
  (`uninstall.sh`).
- `send-trueconf-message.sh` — drop-in Zabbix alertscript wrapper that
  auto-selects queue or direct mode.
- Logging to file or stderr, level configurable via `config.toml`.
