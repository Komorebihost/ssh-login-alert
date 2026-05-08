#!/bin/bash
# =============================================================================
#  install.sh — Universal installer for SSH Login Notifier
#  Usage: sudo bash install.sh [--full]
#
#  Supported distributions:
#    Debian / Ubuntu and derivatives  (apt)
#    RHEL / CentOS / AlmaLinux / Rocky 8+ / Fedora  (dnf)
#    CentOS 7 / RHEL 7  (yum)
#    Arch / Manjaro  (pacman)
#    openSUSE / SLES  (zypper)
#    Alpine  (apk)
#
#  DISCLAIMER:
#  This installer modifies /etc/ssh/sshrc and creates /var/log/ssh_notify.log.
#  Always review the script before running it as root.
#  A timestamped backup of any existing /etc/ssh/sshrc is created automatically.
# =============================================================================

set -e

FULL=false
[ "$1" = "--full" ] && FULL=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
err()  { printf "${RED}[ERR]${NC}   %s\n" "$1"; exit 1; }
info() { printf "${CYAN}[..]${NC}    %s\n" "$1"; }

[ "$(id -u)" -ne 0 ] && err "Run with sudo: sudo bash install.sh"

# ---------------------------------------------------------------------------
# DISTRO DETECTION
# ---------------------------------------------------------------------------

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_ID_LIKE="${ID_LIKE,,}"
    elif [ -f /etc/alpine-release ]; then
        DISTRO_ID="alpine"
    else
        DISTRO_ID="unknown"
    fi
}

get_pkg_info() {
    if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" || \
          "$DISTRO_ID_LIKE" == *"debian"* || "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
        echo "apt mailutils"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID_LIKE" == *"rhel"* || \
            "$DISTRO_ID_LIKE" == *"fedora"* || "$DISTRO_ID" == "almalinux" || \
            "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "centos" || \
            "$DISTRO_ID" == "rhel" ]]; then
        if command -v dnf &>/dev/null; then
            echo "dnf s-nail"
        else
            echo "yum mailx"
        fi
    elif [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID" == "manjaro" || \
            "$DISTRO_ID_LIKE" == *"arch"* ]]; then
        echo "pacman s-nail"
    elif [[ "$DISTRO_ID" == "opensuse"* || "$DISTRO_ID" == "sles" || \
            "$DISTRO_ID_LIKE" == *"suse"* ]]; then
        echo "zypper mailx"
    elif [[ "$DISTRO_ID" == "alpine" ]]; then
        echo "apk mailx"
    else
        echo "unknown unknown"
    fi
}

pkg_install() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
        dnf)    dnf install -y "$pkg" ;;
        yum)    yum install -y "$pkg" ;;
        pacman) pacman -S --noconfirm "$pkg" ;;
        zypper) zypper install -y "$pkg" ;;
        apk)    apk add --no-cache "$pkg" ;;
        *)      return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# INSTALL MAIL CLIENT
# ---------------------------------------------------------------------------

install_mail() {
    if command -v mail &>/dev/null; then
        ok "mail already installed"
        return 0
    fi

    if [ "$PKG_MANAGER" = "unknown" ] || [ "$MAIL_PKG" = "unknown" ]; then
        warn "Could not detect package manager — install a mail client manually."
        warn "See README: Troubleshooting email delivery"
        return 1
    fi

    info "Installing ${MAIL_PKG} via ${PKG_MANAGER}..."
    if pkg_install "$MAIL_PKG" &>/dev/null; then
        ok "${MAIL_PKG} installed"
    else
        warn "${MAIL_PKG} installation failed — see README: Troubleshooting email delivery"
    fi
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

detect_distro
read -r PKG_MANAGER MAIL_PKG <<< "$(get_pkg_info)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Detected distro : ${DISTRO_ID:-unknown}"
info "Package manager : ${PKG_MANAGER}"
info "Mail package    : ${MAIL_PKG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $FULL; then
    SRC="sshrc-full"
    warn "Installing FULL version (HTML email, geo-lookup, rate limiting, full log)"
else
    SRC="sshrc"
    ok "Installing MINIMAL version (plain-text email, log on brute-force only)"
fi

[ -f "$SRC" ] || err "File '$SRC' not found. Run this script from the repo directory."

# Backup existing sshrc
if [ -f /etc/ssh/sshrc ]; then
    BACKUP="/etc/ssh/sshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/ssh/sshrc "$BACKUP"
    warn "Existing /etc/ssh/sshrc backed up to $BACKUP"
fi

cp "$SRC" /etc/ssh/sshrc
chmod +x /etc/ssh/sshrc
ok "Script installed at /etc/ssh/sshrc"

# Log file
LOG_FILE="/var/log/ssh_notify.log"
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    ok "Log file created: $LOG_FILE"
else
    ok "Log file already exists: $LOG_FILE"
fi

echo ""
echo "Checking / installing dependencies:"
install_mail

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Installation complete. No sshd restart required."
echo ""
echo "  Next steps:"
echo "  1. Edit RECIPIENTS in /etc/ssh/sshrc"
echo "     e.g. RECIPIENTS=(\"you@gmail.com\")"
echo "  2. Add trusted IPs to WHITELIST_IPS"
echo "  3. Test:"
echo "     SSH_CONNECTION='1.2.3.4 54321 5.6.7.8 22' USER=test bash /etc/ssh/sshrc"
echo "     sleep 3 && tail /var/log/ssh_notify.log"
echo ""
echo "  If emails are not delivered, see README: Troubleshooting email delivery"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
