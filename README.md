# ssh-login-alert

Sends an email alert on every successful SSH login. Two versions: **minimal** (plain text, logs only on confirmed brute-force) and **full** (HTML email, IP geolocation, rate limiting, structured log).

Uses `/etc/ssh/sshrc` — OpenSSH's native per-login hook — without touching `sshd_config` and without any risk of locking yourself out.

> **Disclaimer:** This tool is a best-effort notification aid. It should not be your only line of defence against unauthorised access. Always use key-based authentication, a properly configured firewall, and an intrusion prevention system such as [fail2ban](https://github.com/fail2ban/fail2ban). The authors accept no liability for missed or delayed alerts, false positives, or any security incidents arising from the use of this software.

---

## Versions

### `sshrc` — minimal *(recommended)*

- Plain-text email on every non-whitelisted login
- Brute-force detection: if the source IP had ≥ N failed attempts in the last hour, the alert includes a warning and a log entry is written
- No log written for clean logins
- No external dependencies beyond `mail`

**Example alert:**

```
SSH login detected

Host    : server.example.com
User    : mario
IP      : 185.23.11.4
Date    : 2026-05-07 14:32:10 UTC

WARNING: 7 failed attempt(s) in the last 60 min
before this successful login — possible brute-force.
```

### `sshrc-full` — full

Everything in the minimal version, plus:

- HTML email with professional layout and colour-coded SSH port badge
- IP geolocation via [ip-api.com](http://ip-api.com) (free, no API key, private ranges skipped)
- Per-IP rate limiting to suppress duplicate alerts on rapid re-logins
- Structured log with automatic rotation (no logrotate dependency)
- Brute-force warning block rendered inline in the HTML email

---

## Requirements

| Component | Min version | Notes |
|---|---|---|
| OpenSSH | 5.x+ | `sshrc` supported since early versions |
| bash | 4.x+ | |
| mail | any | Installed automatically by the installer |
| curl | any | Full version only — install manually if needed |

---

## Installation

```bash
git clone https://github.com/Komorebihost/ssh-login-alert.git
cd ssh-login-alert
sudo bash install.sh           # minimal version
sudo bash install.sh --full    # full version
```

The installer detects your Linux distribution and installs the appropriate mail package:

| Distribution | Package manager | Mail package |
|---|---|---|
| Debian / Ubuntu / Mint | apt | mailutils |
| RHEL / CentOS 8+ / Fedora / AlmaLinux / Rocky | dnf | s-nail |
| CentOS 7 / RHEL 7 | yum | mailx |
| Arch / Manjaro | pacman | s-nail |
| openSUSE / SLES | zypper | mailx |
| Alpine | apk | mailx |

The installer also:
- Backs up any existing `/etc/ssh/sshrc` with a timestamp
- Copies and makes the chosen script executable
- Creates `/var/log/ssh_notify.log` with restricted permissions (`640`)

**No sshd restart required.**

---

## Configuration

Edit the variables at the top of `/etc/ssh/sshrc`:

```bash
# One or more recipients
RECIPIENTS=("root")
# RECIPIENTS=("you@gmail.com" "alerts@example.com")

# Trusted IPs — no alert sent for these
WHITELIST_IPS=(
    "127.0.0.1"
    "::1"
    # "1.2.3.4"
)

# Brute-force threshold (failed attempts in the last hour)
FAILED_THRESHOLD=3
```

Full version only:

```bash
RATE_LIMIT_SECONDS=60    # min seconds between alerts for the same IP
GEO_LOOKUP=true          # enable/disable IP geolocation
GEO_TIMEOUT=3            # curl timeout for geo API (seconds)
MAIL_TIMEOUT=10          # mail delivery timeout (seconds)
MAX_LOG_LINES=10000      # log rotation trigger
```

---

## Testing

```bash
# Simulate a login from an external IP
sudo SSH_CONNECTION="1.2.3.4 54321 5.6.7.8 22" USER=testuser bash /etc/ssh/sshrc
sleep 3

# Check the log
sudo tail /var/log/ssh_notify.log

# Read local root mail (if RECIPIENTS contains "root")
sudo mail -u root
```

---

## Updating

### With git

```bash
git pull origin main
sudo bash install.sh    # or --full
```

The installer backs up the current `/etc/ssh/sshrc` before overwriting it.

### Manual

1. Download the new `sshrc` or `sshrc-full` from the repo.
2. Re-apply your customisations (`RECIPIENTS`, `WHITELIST_IPS`, thresholds).
3. Replace the installed script:

```bash
sudo cp sshrc /etc/ssh/sshrc
sudo chmod +x /etc/ssh/sshrc
```

No sshd restart needed.

---

## Troubleshooting email delivery

On most servers `mailutils` works out of the box because a working MTA (Postfix, Exim, Sendmail) is already present. If emails are not delivered, verify first:

```bash
echo "test" | mail -s "test" you@example.com
```

If that fails, diagnose:

```bash
# Check what MTA is installed and running
systemctl status postfix exim4 exim sendmail 2>/dev/null

# Check the mail log
tail -30 /var/log/mail.log
```

### Option: use msmtp as a lightweight relay

If no MTA is available or the existing one is misconfigured, `msmtp` is the recommended lightweight alternative. It requires no daemon, works on all distros, and relays through any external SMTP provider.

**Install:**

```bash
# Debian / Ubuntu
apt install msmtp msmtp-mta -y

# RHEL / Fedora
dnf install msmtp -y

# Arch
pacman -S msmtp

# Alpine
apk add msmtp
```

**Configure `/etc/msmtprc`:**

```
defaults
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

# Gmail example
# Requires an App Password — enable 2FA first, then generate one at:
# https://myaccount.google.com/apppasswords
account        default
host           smtp.gmail.com
port           587
auth           on
from           your@gmail.com
user           your@gmail.com
password       your-app-password
```

```bash
chmod 600 /etc/msmtprc
```

**Generic SMTP example:**

```
account        default
host           mail.yourprovider.com
port           587
auth           on
from           notify@yourdomain.com
user           notify@yourdomain.com
password       yourpassword
```

**Test:**

```bash
echo "test" | mail -s "test" you@example.com
tail -10 /var/log/msmtp.log
```

---

## Uninstalling

```bash
sudo rm /etc/ssh/sshrc
sudo rm /var/log/ssh_notify.log        # optional
```

---

## How it works

OpenSSH executes `/etc/ssh/sshrc` automatically for every successful login, before handing control to the user's shell. The script runs entirely in the background (`&` + `disown`) so it never delays the session.

**Note on shell compatibility:** sshd always runs `sshrc` via `/bin/sh`, ignoring the shebang. On systems where `/bin/sh` is not bash (e.g. Debian with `dash`), bash-specific syntax like arrays would fail. Both scripts handle this with a re-exec guard at the top:

```sh
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
```

This transparently re-invokes the script under bash whenever `/bin/sh` is not bash.

Brute-force detection queries `journalctl` (systemd) or `/var/log/auth.log` (fallback) for `Failed` entries matching the source IP in the last 60 minutes.

---

## License

MIT — see [LICENSE](LICENSE)
