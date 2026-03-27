# TrueConf Zabbix Sender

![TrueConf Zabbix Sender — Monitoring to ChatOps](assets/project-thumbnail.svg)

A lightweight script that lets Zabbix send alert notifications as direct
TrueConf chat messages.

## How it works

### Service mode (recommended for production)

A systemd service (`trueconf-zabbix-sender`) keeps a single persistent
WebSocket connection to TrueConf Server. When Zabbix triggers an alert,
`send-trueconf-message.sh` converts the recipient emails to TrueConf IDs,
writes a small JSON task file to the `queue/` directory, and exits immediately
(exit 0). The running service picks it up within ~1 second and delivers the
message without reconnecting.

This design handles bursts of alerts natively. Recipients within the same
alert are delivered in parallel; multiple alerts are processed in arrival order.
If the service is temporarily down, task files accumulate in the queue and are
delivered automatically when the service comes back up.

### Direct mode (fallback)

When the `queue/` directory does not exist (service not installed),
`send-trueconf-message.sh` falls back to direct mode: it connects to TrueConf,
sends the message, and disconnects. This is fine for very infrequent alerts
(say, one every few days) but is not recommended for bursts.

### Email → TrueConf ID mapping

Email addresses from Zabbix (`user@example.com`) are automatically remapped
to TrueConf IDs (`user@tconf.example.com`) using the domain mapping in
`config.toml`. The mapping is case-insensitive; the username part is preserved.

## File overview

| File | Description |
|------|-------------|
| `trueconf_sender.py` | Main Python script (direct + service modes) |
| `config.toml` | Configuration — server, credentials, domain mapping |
| `send-trueconf-message.sh` | Shell wrapper called by Zabbix |
| `install.sh` | Automated installer for Ubuntu 24.04 |
| `uninstall.sh` | Removes all installed files, symlinks, and the service |
| `trueconf-zabbix-sender.service` | Optional systemd unit for service mode |

## Installation on Ubuntu 24.04 (Zabbix server)

Copy the entire project directory to the server and run:

```bash
sudo ./install.sh
```

With the optional persistent service:

```bash
sudo ./install.sh --install-service
```

The installer:
1. Checks Python ≥ 3.10
2. Installs `python3-venv` and `python3-pip`
3. Copies files to `/opt/trueconf-zabbix-sender/`
4. Creates a Python virtual environment and installs `python-trueconf-bot`
5. Creates a symlink in `/usr/lib/zabbix/alertscripts/`
6. Sets ownership to `zabbix:zabbix` with secure permissions

## Configuration

Edit `/opt/trueconf-zabbix-sender/config.toml`:

```toml
[server]
host       = "tconf.example.com"
verify_ssl = true   # set false if the server uses a private/corporate CA cert

[credentials]
login    = "your_bot_account"
password = "your_password"

[email_mapping]
from_domain = "example.com"
to_domain   = "tconf.example.com"
```

### SSL certificate

If the TrueConf server uses a corporate CA certificate, install it on Ubuntu
and then set `verify_ssl = true`:

```bash
sudo cp corporate-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

## Manual testing

```bash
/opt/trueconf-zabbix-sender/send-trueconf-message.sh \
  "alice@example.com bob@example.com" \
  "Zabbix test message"
```

Exit codes: `0` success, `1` usage error, `2` config error, `3` delivery failure.

## Zabbix media type configuration

1. **Administration → Media types → Create media type**
   - Type: **Script**
   - Script name: `send-trueconf-message.sh`
   - Script parameters:
     - `{ALERT.SENDTO}` — recipient addresses (space-separated)
     - `{ALERT.MESSAGE}` — alert message body

2. **Users → (user) → Media → Add**
   - Type: TrueConf (the media type created above)
   - Send to: `alice@example.com bob@example.com`
     _(space-separated list of email addresses)_

## Service mode — setup and operation

The service is the **recommended** deployment for production Zabbix servers.

```bash
# Install with service unit file
sudo ./install.sh --install-service

# Enable and start
sudo systemctl enable --now trueconf-zabbix-sender

# View live logs
journalctl -u trueconf-zabbix-sender -f

# Stop
sudo systemctl stop trueconf-zabbix-sender
```

### Error handling

If message delivery fails (e.g. recipient not found on the server), the queue
task file is renamed to `ERROR_<original-name>.json` in the `queue/` directory
and the error is logged. These files can be reviewed and removed manually:

```bash
ls /opt/trueconf-zabbix-sender/queue/ERROR_*.json   # list failed tasks
cat /opt/trueconf-zabbix-sender/queue/ERROR_*.json  # inspect them
rm  /opt/trueconf-zabbix-sender/queue/ERROR_*.json  # clean up
```

Note that queue mode exits with code 0 as soon as the task file is written,
before the message is actually delivered. Zabbix considers the alert "sent"
at that point. Delivery errors appear only in the service log.

## Uninstallation

Run on the Ubuntu server from the original project directory:

```bash
sudo ./uninstall.sh
```

What it removes:
1. Stops and disables the `trueconf-zabbix-sender` systemd service (if installed)
2. Removes `/etc/systemd/system/trueconf-zabbix-sender.service`
3. Removes the symlink `/usr/lib/zabbix/alertscripts/send-trueconf-message.sh`
4. Removes the entire `/opt/trueconf-zabbix-sender/` directory (venv, queue, config, scripts)

If there are unprocessed task files in the queue at the time of uninstall,
the script prints a warning before removing them.

## Requirements

- Python 3.10 or higher (Ubuntu 24.04 ships with Python 3.12)
- Network access from the Zabbix server to the TrueConf Server on port 443
- A valid TrueConf Server account for the bot (the account must already exist)
- TrueConf Server 5.5 or above (Chatbot API support)

## License

This project is licensed under the GNU General Public License v3.0.
See the [LICENSE](LICENSE) file for details.
