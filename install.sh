#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605172316-git
# @@Author           :  Jason Hempstead
# @@Contact          :  jason@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  install.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, May 17, 2026 21:47 EDT
# @@File             :  install.sh
# @@Description      :  Install and configure Incus with SimpleStreams image registry and Nginx reverse proxy
# @@Changelog        :  Add distro-aware Incus install, SimpleStreams registry, Nginx reverse proxy, GitHub script deployment
# @@TODO             :  Better documentation
# @@Other            :
# @@Resource         :  https://linuxcontainers.org/incus/
# @@Terminal App     :  no
# @@sudo/root        :  yes
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Guard: Alpine ships ash; install bash and re-exec if needed
if [ -z "${BASH_VERSION:-}" ]; then
  if [ -f /etc/alpine-release ] && ! command -v bash >/dev/null 2>&1; then
    apk update -q 2>/dev/null || true
    apk add --no-progress bash 2>/dev/null || true
  fi
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf 'ERROR: bash is required. Install bash and re-run: bash %s\n' "$0" >&2
  exit 1
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -
# script variables
APPNAME="${0##*/}"
VERSION="202605172316-git"
RUN_USER="${USER:-root}"
SET_UID="${UID}"
SCRIPT_SRC_DIR="${BASH_SOURCE%/*}"
INCUS_CWD="${PWD}"
INCUS_EXIT_STATUS=0
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Define color variables
PRINTF_SET_BLACK='\e[1;30m'
PRINTF_SET_RED='\e[0;31m'
PRINTF_SET_GREEN='\e[0;32m'
PRINTF_SET_YELLOW='\e[1;33m'
PRINTF_SET_BLUE='\e[1;34m'
PRINTF_SET_PURPLE='\e[0;35m'
PRINTF_SET_CYAN='\e[0;36m'
PRINTF_SET_WHITE='\e[1;37m'
PRINTF_SET_RESET='\e[0m'
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Default configuration — all overridable via environment
INCUS_ARCH="${INCUS_ARCH:-both}"
INCUS_FQDN="${INCUS_FQDN:-$(hostname --fqdn 2>/dev/null || hostname -f 2>/dev/null || hostname)}"
INCUS_SIMPLESTREAMS_PORT="${INCUS_SIMPLESTREAMS_PORT:-8088}"
INCUS_SIMPLESTREAMS_DIR="${INCUS_SIMPLESTREAMS_DIR:-/var/lib/incus-simplestreams}"
INCUS_SIMPLESTREAMS_USER="${INCUS_SIMPLESTREAMS_USER:-incus-streams}"
INCUS_NGINX_CONF_DIR="${INCUS_NGINX_CONF_DIR:-/etc/nginx/vhosts.d}"
INCUS_NGINX_LOG_DIR="${INCUS_NGINX_LOG_DIR:-/var/log/nginx}"
INCUS_GITHUB_OWNER="${INCUS_GITHUB_OWNER:-scriptmgr}"
INCUS_GITHUB_REPO="${INCUS_GITHUB_REPO:-incus}"
INCUS_GITHUB_BRANCH="${INCUS_GITHUB_BRANCH:-main}"
INCUS_SCRIPTS_DEST="${INCUS_SCRIPTS_DEST:-/usr/local/bin}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# script functions
if [ -n "${NO_COLOR+x}" ] || [ "${SHOW_RAW:-}" = "true" ]; then
  __printf_color() { printf '%s\n' "$1"; }
else
  __printf_color() { [ -t 1 ] && printf '%b%s%b\n' "${2:-$PRINTF_SET_RESET}" "$1" "$PRINTF_SET_RESET" || printf '%s\n' "$1"; }
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
__cmd_exists()      { command -v "$1" &>/dev/null; }
__function_exists() { declare -F "$1" &>/dev/null; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__info()  { __printf_color "  [INFO]  $*" "$PRINTF_SET_CYAN"; }
__ok()    { __printf_color "  [ OK ]  $*" "$PRINTF_SET_GREEN"; }
__warn()  { __printf_color "  [WARN]  $*" "$PRINTF_SET_YELLOW"; }
__error() { __printf_color "  [ERR ]  $*" "$PRINTF_SET_RED"; }
__step()  { __printf_color "\n  >>>>  $*" "$PRINTF_SET_BLUE"; }
__fatal() { __error "$*"; exit 1; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
__help() {
  printf '%s\n' "
Usage: ${APPNAME} [OPTIONS]

Install and configure Incus with a SimpleStreams image registry
and Nginx reverse proxy. Safe to re-run — all steps are idempotent.

Options:
  -a, --arch ARCH     Architectures to support: amd64, arm64, both (default: both)
  -v, --version       Show version and exit
  -h, --help          Show this help and exit
      --no-color      Disable color output
      --debug         Enable debug output

Environment variables (all optional — script uses sane defaults):
  INCUS_FQDN                  Registry hostname (default: hostname --fqdn)
  INCUS_SIMPLESTREAMS_PORT    Backend HTTP port (default: 8088)
  INCUS_SIMPLESTREAMS_DIR     Image storage root (default: /var/lib/incus-simplestreams)
  INCUS_SIMPLESTREAMS_USER    Service user (default: incus-streams)
  INCUS_NGINX_CONF_DIR        Nginx vhost config dir (default: /etc/nginx/vhosts.d)
  INCUS_NGINX_LOG_DIR         Nginx log dir (default: /var/log/nginx)
  INCUS_GITHUB_OWNER          GitHub org/user for script download (default: scriptmgr)
  INCUS_GITHUB_REPO           GitHub repo for script download (default: incus)
  INCUS_GITHUB_BRANCH         Branch to pull scripts from (default: main)
  INCUS_SCRIPTS_DEST          Install destination for scripts (default: /usr/local/bin)
  GITHUB_TOKEN                Optional GitHub token for private repos or rate-limit bypass

Supported distributions:
  Debian, Ubuntu, and derivatives  (zabbly stable repo)
  Fedora                           (ganto/incus COPR)
  RHEL, CentOS, Rocky, AlmaLinux  (EPEL + ganto/incus COPR)
  Arch Linux and derivatives       (extra repo)
  openSUSE Tumbleweed / Leap       (OBS home:ganto:incus)
  Alpine Linux                     (community repo)

Examples:
  ${APPNAME}
  ${APPNAME} --arch amd64
  INCUS_FQDN=images.example.com ${APPNAME}
  INCUS_FQDN=images.example.com INCUS_SIMPLESTREAMS_PORT=9000 ${APPNAME}
"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__version() { printf '%s %s\n' "${APPNAME}" "${VERSION}"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Distro detection
__distro_id=""
__distro_like=""
__distro_version=""
__distro_codename=""
__distro_family=""

__detect_distro() {
  [ -f /etc/os-release ] || __fatal "/etc/os-release not found — cannot detect distribution"
  # shellcheck source=/dev/null
  . /etc/os-release
  __distro_id="${ID:-unknown}"
  __distro_like="${ID_LIKE:-}"
  __distro_version="${VERSION_ID:-}"
  __distro_codename="${VERSION_CODENAME:-}"

  case "${__distro_id}" in
    debian|ubuntu|linuxmint|pop|elementary|kali|parrot|raspbian|mx|zorin|\
tails|deepin|bodhi|peppermint|neon|pureos|devuan|antix|lmde|sparky|bunsenlabs|\
vanilla|tuxedo|xerolinux|buntu|kubuntu|lubuntu|xubuntu|edubuntu|ubuntustudio)
      __distro_family="debian" ;;
    fedora|nobara|ultramarine|bazzite|silverblue|kinoite|sericea|onyx)
      __distro_family="fedora" ;;
    rhel|centos|rocky|almalinux|ol|scientific|eurolinux|springdale|centos-stream|\
oraclelinux|cloudlinux|navix|vzlinux)
      __distro_family="rhel" ;;
    arch|manjaro|endeavouros|garuda|artix|arcolinux|blackarch|cachyos|crystal|\
parabola|hyperbola|archcraft|blendos)
      __distro_family="arch" ;;
    opensuse-tumbleweed|opensuse-leap|opensuse|sles|sled|microos|aeon|kalpa)
      __distro_family="suse" ;;
    alpine)
      __distro_family="alpine" ;;
    *)
      case "${__distro_like}" in
        *debian*|*ubuntu*) __distro_family="debian" ;;
        *fedora*)          __distro_family="fedora" ;;
        *rhel*|*centos*)   __distro_family="rhel" ;;
        *arch*)            __distro_family="arch" ;;
        *suse*)            __distro_family="suse" ;;
        *) __fatal "Unsupported distribution: ${__distro_id} (ID_LIKE='${__distro_like}')" ;;
      esac
      ;;
  esac
  __info "Detected: ${__distro_id} ${__distro_version:-} (family: ${__distro_family})"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Package manager wrappers
__apt()    { DEBIAN_FRONTEND=noninteractive apt-get -y -qq "$@"; }
__dnf()    { dnf -y -q "$@"; }
__pacman() { pacman -S --noconfirm --needed "$@"; }
__zypper() { zypper -n install --no-recommends "$@"; }
__apk()    { apk add --no-cache "$@"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Install Incus per distro family
__install_incus_debian() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  __info "Adding zabbly stable repository"
  __apt install curl gpg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.zabbly.com/key.asc \
    | gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg

  local codename="${__distro_codename}"
  # Derivatives may not set VERSION_CODENAME — try fallbacks
  if [ -z "${codename}" ]; then
    codename="$(. /etc/upstream-release/lsb-release 2>/dev/null \
                && echo "${DISTRIB_CODENAME:-}" || true)"
    [ -z "${codename}" ] && codename="$(lsb_release -sc 2>/dev/null || true)"
  fi
  [ -n "${codename}" ] || __fatal "Cannot determine release codename for apt repo"

  printf 'deb [signed-by=/etc/apt/keyrings/zabbly.gpg] https://pkgs.zabbly.com/incus/stable %s main\n' \
    "${codename}" > /etc/apt/sources.list.d/zabbly-incus-stable.list
  __apt update
  __apt install incus
  __ok "incus installed"
}

__install_incus_fedora() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  __info "Enabling neelc/incus COPR"
  __dnf install dnf-plugins-core
  dnf copr enable -y neelc/incus
  __dnf install incus incus-tools
  __ok "incus installed"
}

__install_incus_rhel() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  local major="${__distro_version%%.*}"
  __info "Installing EPEL and enabling neelc/incus COPR"
  __dnf install dnf-plugins-core
  if ! rpm -q epel-release >/dev/null 2>&1; then
    __dnf install \
      "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm" \
      2>/dev/null || __dnf install epel-release || true
  fi
  if [ "${major}" -ge 10 ]; then
    # dnf copr enable does not support el10 for neelc/incus; fetch repo file directly
    __info "Adding neelc/incus repo for el${major}"
    curl -q -LSsf \
      "https://copr.fedorainfracloud.org/coprs/neelc/incus/repo/rhel+epel-${major}/neelc-incus-rhel+epel-${major}.repo" \
      -o "/etc/yum.repos.d/neelc-incus-rhel+epel-${major}.repo"
  else
    dnf copr enable -y neelc/incus
    # CRB provides build-time deps for el9
    dnf config-manager --enable crb 2>/dev/null || true
  fi
  __dnf install incus incus-tools
  __ok "incus installed"
}

__install_incus_arch() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  __pacman incus
  __ok "incus installed"
}

__install_incus_suse() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  local obs_suffix
  case "${__distro_id}" in
    opensuse-tumbleweed|microos|aeon|kalpa) obs_suffix="openSUSE_Tumbleweed" ;;
    opensuse-leap)  obs_suffix="openSUSE_Leap_${__distro_version}" ;;
    sles|sled)      obs_suffix="SLE_${__distro_version%%.*}" ;;
    *)              obs_suffix="openSUSE_Tumbleweed" ;;
  esac
  __info "Adding OBS home:ganto:incus (${obs_suffix})"
  zypper addrepo --refresh \
    "https://download.opensuse.org/repositories/home:ganto:incus/${obs_suffix}/home:ganto:incus.repo" \
    home-ganto-incus 2>/dev/null || true
  zypper -n refresh home-ganto-incus 2>/dev/null || true
  __zypper incus incus-tools
  __ok "incus installed"
}

__install_incus_alpine() {
  if __cmd_exists incus; then
    __ok "incus already installed ($(incus --version 2>/dev/null || echo '?'))"
    return 0
  fi
  # Ensure community repo is present
  if ! grep -q '^[^#].*community' /etc/apk/repositories 2>/dev/null; then
    local ver
    ver="$(cut -d. -f1-2 /etc/alpine-release 2>/dev/null)"
    printf 'https://dl-cdn.alpinelinux.org/alpine/v%s/community\n' "${ver}" \
      >> /etc/apk/repositories
    apk update -q
  fi
  __apk curl incus incus-client incus-openrc
  __ok "incus installed"
}


__install_incus() {
  __step "Installing Incus"
  "__install_incus_${__distro_family}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__configure_incus() {
  __step "Configuring Incus"
  # Start service
  if __cmd_exists systemctl; then
    systemctl enable --now incus incus-startup 2>/dev/null \
      || systemctl enable --now incus 2>/dev/null || true
  elif __cmd_exists rc-service; then
    rc-update add incusd default 2>/dev/null || true
    rc-service incusd start 2>/dev/null || true
  fi

  # Wait for socket (up to 45s — OpenRC daemons can be slower to initialize)
  local i=0
  while [ "${i}" -lt 45 ]; do
    incus info >/dev/null 2>&1 && break
    sleep 1; i=$((i + 1))
  done
  incus info >/dev/null 2>&1 || __fatal "Incus daemon not responding after start"

  # Idempotent init — skip if storage pools already exist
  if incus storage list 2>/dev/null | grep -qE '^\| [a-zA-Z]'; then
    __ok "Incus already initialized"
    return 0
  fi

  __info "Running: incus admin init --auto"
  incus admin init --auto
  __ok "Incus initialized"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__install_incus_simplestreams() {
  __step "Installing incus-simplestreams"
  if __cmd_exists incus-simplestreams; then
    __ok "incus-simplestreams already installed"
    return 0
  fi

  local installed=false

  # Try package manager first
  case "${__distro_family}" in
    debian)
      if apt-cache show incus-simplestreams >/dev/null 2>&1; then
        __apt install incus-simplestreams && installed=true
      fi ;;
    fedora|rhel)
      if dnf info incus-simplestreams >/dev/null 2>&1; then
        __dnf install incus-simplestreams && installed=true
      fi ;;
    arch)
      if pacman -Ss '^incus-simplestreams$' 2>/dev/null | grep -q incus-simplestreams; then
        __pacman incus-simplestreams && installed=true
      fi ;;
    suse)
      if zypper info incus-simplestreams >/dev/null 2>&1; then
        __zypper incus-simplestreams && installed=true
      fi ;;
    alpine)
      # incus-simplestreams is shipped in incus-utils (stable) or incus-feature-utils (feature)
      if apk info incus-utils >/dev/null 2>&1; then
        __apk incus-utils && installed=true
      elif apk info incus-feature-utils >/dev/null 2>&1; then
        __apk incus-feature-utils && installed=true
      fi ;;
  esac

  if [ "${installed}" = "true" ]; then
    __ok "incus-simplestreams installed from package manager"
    return 0
  fi

  # Fall back to GitHub release binary
  __info "Package not available — fetching binary from GitHub"
  local host_arch
  host_arch="$(uname -m)"
  case "${host_arch}" in
    x86_64|aarch64) ;;
    *) __fatal "Unsupported host architecture: ${host_arch}" ;;
  esac

  local api_url="https://api.github.com/repos/lxc/incus/releases/latest"
  local bin_url
  bin_url="$(curl -q -LSsf --max-time 30 "${api_url}" \
    | grep -oE '"browser_download_url": *"[^"]*incus-simplestreams[^"]*[._-]'"${host_arch}"'"' \
    | head -1 | cut -d'"' -f4)"

  if [ -n "${bin_url}" ]; then
    curl -q -LSsf --max-time 120 "${bin_url}" -o /usr/local/bin/incus-simplestreams
    chmod 755 /usr/local/bin/incus-simplestreams
    __ok "incus-simplestreams installed from GitHub release"
    return 0
  fi

  # Last resort: build with go if available
  if __cmd_exists go; then
    __info "Building incus-simplestreams with go install"
    GOBIN=/usr/local/bin go install github.com/lxc/incus/cmd/incus-simplestreams@latest
    __ok "incus-simplestreams built and installed"
    return 0
  fi

  __fatal "Cannot install incus-simplestreams: no package, no release binary, no go toolchain"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__configure_simplestreams() {
  __step "Configuring SimpleStreams image server"

  # Create service user if not root-run service
  if ! id "${INCUS_SIMPLESTREAMS_USER}" >/dev/null 2>&1; then
    __info "Creating service user: ${INCUS_SIMPLESTREAMS_USER}"
    useradd --system --shell /sbin/nologin \
      --home-dir "${INCUS_SIMPLESTREAMS_DIR}" \
      --comment "Incus SimpleStreams image server" \
      "${INCUS_SIMPLESTREAMS_USER}" 2>/dev/null \
      || adduser -S -H -D -s /sbin/nologin "${INCUS_SIMPLESTREAMS_USER}" 2>/dev/null || true
  fi

  # Create directory structure
  mkdir -p \
    "${INCUS_SIMPLESTREAMS_DIR}/streams/v1" \
    "${INCUS_SIMPLESTREAMS_DIR}/images"

  # Initialize index files if not present
  if [ ! -f "${INCUS_SIMPLESTREAMS_DIR}/streams/v1/index.json" ]; then
    __info "Initializing SimpleStreams directory structure"
    cat > "${INCUS_SIMPLESTREAMS_DIR}/streams/v1/index.json" << 'EOJSON'
{
  "format": "index:1.0",
  "index": {
    "images": {
      "datatype": "image-downloads",
      "format": "products:1.0",
      "path": "streams/v1/images.json",
      "updated": "",
      "products": []
    }
  }
}
EOJSON

    printf '{"content_id":"images","datatype":"image-downloads","format":"products:1.0","products":{},"updated":""}\n' \
      > "${INCUS_SIMPLESTREAMS_DIR}/streams/v1/images.json"
  else
    __ok "SimpleStreams directory already initialized"
  fi

  chown -R "${INCUS_SIMPLESTREAMS_USER}:${INCUS_SIMPLESTREAMS_USER}" \
    "${INCUS_SIMPLESTREAMS_DIR}" 2>/dev/null || true

  # Install python3 if needed (for the HTTP server backend)
  if ! __cmd_exists python3; then
    __info "Installing python3 (needed for HTTP backend)"
    case "${__distro_family}" in
      debian) __apt install python3 ;;
      fedora) __dnf install python3 ;;
      rhel)   __dnf install python3 ;;
      arch)   __pacman python ;;
      suse)   __zypper python3 ;;
      alpine) __apk python3 ;;
    esac
  fi

  # Create systemd service
  if __cmd_exists systemctl; then
    if systemctl is-enabled incus-simplestreams.service >/dev/null 2>&1; then
      __ok "incus-simplestreams.service already enabled"
    else
      __info "Creating systemd unit: incus-simplestreams.service"
      cat > /etc/systemd/system/incus-simplestreams.service << EOUNIT
[Unit]
Description=Incus SimpleStreams Image Server
Documentation=https://linuxcontainers.org/incus/docs/main/
After=network.target

[Service]
Type=simple
User=${INCUS_SIMPLESTREAMS_USER}
WorkingDirectory=${INCUS_SIMPLESTREAMS_DIR}
ExecStart=python3 -m http.server --bind 127.0.0.1 ${INCUS_SIMPLESTREAMS_PORT} --directory ${INCUS_SIMPLESTREAMS_DIR}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=incus-simplestreams
# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INCUS_SIMPLESTREAMS_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOUNIT
      systemctl daemon-reload
      systemctl enable --now incus-simplestreams.service
    fi

  elif __cmd_exists rc-update; then
    # OpenRC (Alpine)
    if [ ! -f /etc/init.d/incus-simplestreams ]; then
      __info "Creating OpenRC service: incus-simplestreams"
      cat > /etc/init.d/incus-simplestreams << EORC
#!/sbin/openrc-run
name="incus-simplestreams"
description="Incus SimpleStreams Image Server"
command="/usr/bin/python3"
command_args="-m http.server --bind 127.0.0.1 ${INCUS_SIMPLESTREAMS_PORT} --directory ${INCUS_SIMPLESTREAMS_DIR}"
command_user="${INCUS_SIMPLESTREAMS_USER}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/incus-simplestreams.log"
error_log="/var/log/incus-simplestreams.log"

depend() {
  need net
}
EORC
      chmod +x /etc/init.d/incus-simplestreams
      touch /var/log/incus-simplestreams.log
      chown "${INCUS_SIMPLESTREAMS_USER}" /var/log/incus-simplestreams.log 2>/dev/null || true
      rc-update add incus-simplestreams default
      rc-service incus-simplestreams start
    else
      __ok "OpenRC service already configured"
    fi
  fi

  __ok "SimpleStreams backend: 127.0.0.1:${INCUS_SIMPLESTREAMS_PORT}"
  __ok "Image directory: ${INCUS_SIMPLESTREAMS_DIR}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__install_nginx() {
  __step "Installing Nginx"
  if __cmd_exists nginx; then
    __ok "nginx already installed"
    return 0
  fi
  case "${__distro_family}" in
    debian) __apt install nginx ;;
    fedora) __dnf install nginx ;;
    rhel)   __dnf install nginx ;;
    arch)   __pacman nginx ;;
    suse)   __zypper nginx ;;
    alpine) __apk nginx ;;
  esac
  __ok "nginx installed"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__configure_nginx() {
  __step "Configuring Nginx reverse proxy for ${INCUS_FQDN}"

  mkdir -p "${INCUS_NGINX_CONF_DIR}" "${INCUS_NGINX_LOG_DIR}"

  # Patch main nginx.conf to include vhosts.d if not already included
  local nginx_conf="/etc/nginx/nginx.conf"
  if [ -f "${nginx_conf}" ] && ! grep -qF "${INCUS_NGINX_CONF_DIR}" "${nginx_conf}"; then
    __info "Adding $(basename "${INCUS_NGINX_CONF_DIR}") include to nginx.conf"
    # Replace only the LAST standalone } (which closes the http {} block).
    # Using tac/sed/tac so only the first } in the reversed file is touched.
    # Insert include before the last standalone } (closes the http block).
    # awk tracks the last ^}$ line, then emits the include before it.
    if awk -v inc="    include ${INCUS_NGINX_CONF_DIR}/*.conf;" \
        '/^}$/ { last=NR; lines[NR]=$0; next } { lines[NR]=$0 }
         END { for(i=1;i<=NR;i++){ if(i==last) print inc; print lines[i] } }' \
        "${nginx_conf}" > "${nginx_conf}.new" \
        && mv "${nginx_conf}.new" "${nginx_conf}"; then
      : # patched successfully
    else
      __warn "Could not auto-patch nginx.conf — add manually: include ${INCUS_NGINX_CONF_DIR}/*.conf;"
    fi
  fi

  local conf="${INCUS_NGINX_CONF_DIR}/${INCUS_FQDN}.conf"
  if [ -f "${conf}" ]; then
    __ok "Nginx vhost already exists: ${conf}"
  else
    __info "Writing ${conf}"
    cat > "${conf}" << EONGINX
# Incus SimpleStreams image registry
# Host:    ${INCUS_FQDN}
# Backend: 127.0.0.1:${INCUS_SIMPLESTREAMS_PORT}
# Generated by ${APPNAME} ${VERSION}

upstream incus_simplestreams {
    server 127.0.0.1:${INCUS_SIMPLESTREAMS_PORT};
    keepalive 32;
}

server {
    listen      80;
    listen      [::]:80;
    server_name ${INCUS_FQDN};

    access_log  ${INCUS_NGINX_LOG_DIR}/incus-simplestreams-access.log;
    error_log   ${INCUS_NGINX_LOG_DIR}/incus-simplestreams-error.log warn;

    # No size limit — image files can be several GB
    client_max_body_size    0;
    client_body_timeout     300s;

    # --- Streams index (JSON metadata) ---
    # Short cache so clients see newly published images quickly
    location ~* ^/streams/ {
        proxy_pass              http://incus_simplestreams;
        proxy_http_version      1.1;
        proxy_set_header        Host              \$host;
        proxy_set_header        X-Real-IP         \$remote_addr;
        proxy_set_header        X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_set_header        Connection        "";
        proxy_read_timeout      60s;
        proxy_connect_timeout   10s;
        proxy_buffering         off;
        add_header              Cache-Control "public, max-age=60, must-revalidate" always;
        add_header              X-Content-Type-Options nosniff always;
    }

    # --- Image files (tarballs, squashfs, qcow2) ---
    # Long cache — content-addressed, immutable once published
    location ~* ^/images/ {
        proxy_pass              http://incus_simplestreams;
        proxy_http_version      1.1;
        proxy_set_header        Host              \$host;
        proxy_set_header        X-Real-IP         \$remote_addr;
        proxy_set_header        X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_set_header        Connection        "";

        # Stream large files — do not buffer to disk
        proxy_buffering             off;
        proxy_request_buffering     off;
        proxy_read_timeout          600s;
        proxy_connect_timeout        75s;
        proxy_send_timeout          600s;

        # Range requests — required for resumable downloads
        proxy_set_header            Range             \$http_range;
        proxy_set_header            If-Range          \$http_if_range;
        proxy_hide_header           Accept-Ranges;
        add_header                  Accept-Ranges bytes always;

        add_header                  Cache-Control "public, max-age=86400, immutable" always;
        add_header                  X-Content-Type-Options nosniff always;
    }

    # --- Default ---
    location / {
        proxy_pass              http://incus_simplestreams;
        proxy_http_version      1.1;
        proxy_set_header        Host              \$host;
        proxy_set_header        X-Real-IP         \$remote_addr;
        proxy_set_header        X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_set_header        Connection        "";
        proxy_buffering         off;
        proxy_read_timeout      120s;
        proxy_connect_timeout    10s;
        add_header              Cache-Control "no-store" always;
    }
}
EONGINX
    __ok "Nginx vhost written: ${conf}"
  fi

  # Test config, then enable and reload
  if nginx -t -q 2>/dev/null; then
    if __cmd_exists systemctl; then
      systemctl enable --now nginx 2>/dev/null || true
      systemctl reload nginx 2>/dev/null || systemctl restart nginx
    elif __cmd_exists rc-service; then
      rc-update add nginx default 2>/dev/null || true
      rc-service nginx reload 2>/dev/null || rc-service nginx start
    fi
    __ok "Nginx reloaded"
  else
    nginx -t 2>&1 || true
    __warn "nginx config test failed — fix errors then: nginx -s reload"
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__install_scripts() {
  __step "Installing scripts from GitHub"

  # Auto-detect owner/repo from git remote if not set
  if [ -z "${INCUS_GITHUB_OWNER}" ] || [ -z "${INCUS_GITHUB_REPO}" ]; then
    local remote_url
    remote_url="$(git -C "${SCRIPT_SRC_DIR}" remote get-url origin 2>/dev/null || true)"
    if [ -n "${remote_url}" ]; then
      # Handles both https://github.com/owner/repo and git@github.com:owner/repo
      INCUS_GITHUB_OWNER="$(printf '%s\n' "${remote_url}" \
        | sed 's|.*github\.com[:/]\([^/]*\)/.*|\1|')"
      INCUS_GITHUB_REPO="$(printf '%s\n' "${remote_url}" \
        | sed 's|.*github\.com[:/][^/]*/\([^/.]*\).*|\1|')"
    fi
  fi

  [ -n "${INCUS_GITHUB_OWNER}" ] \
    || __fatal "Cannot determine GitHub owner — set INCUS_GITHUB_OWNER"
  [ -n "${INCUS_GITHUB_REPO}" ] \
    || __fatal "Cannot determine GitHub repo — set INCUS_GITHUB_REPO"

  local api_url="https://api.github.com/repos/${INCUS_GITHUB_OWNER}/${INCUS_GITHUB_REPO}/contents/scripts?ref=${INCUS_GITHUB_BRANCH}"
  __info "Fetching script list: ${api_url}"

  local api_response
  api_response="$(curl -fsSL \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    "${api_url}")" \
    || __fatal "GitHub API call failed — check INCUS_GITHUB_OWNER / INCUS_GITHUB_REPO / INCUS_GITHUB_BRANCH"

  # Parse the JSON array and extract name + download_url for each file entry
  local entries
  entries="$(printf '%s\n' "${api_response}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit('GitHub API error: ' + json.dumps(data))
for item in data:
    if item.get('type') == 'file':
        name = item['name']
        url  = item.get('download_url', '')
        if not url:
            continue
        # Strip .sh extension — scripts live in PATH as bare commands
        bin_name = name[:-3] if name.endswith('.sh') else name
        print(bin_name + '|' + url)
")" || __fatal "Failed to parse GitHub API response"

  mkdir -p "${INCUS_SCRIPTS_DEST}"

  local installed=0
  while IFS='|' read -r bin_name raw_url; do
    [ -n "${bin_name}" ] || continue
    [ -n "${raw_url}" ]  || continue
    __info "Installing ${INCUS_SCRIPTS_DEST}/${bin_name}"
    curl -fsSL \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      "${raw_url}" -o "${INCUS_SCRIPTS_DEST}/${bin_name}"
    chmod 755 "${INCUS_SCRIPTS_DEST}/${bin_name}"
    installed=$((installed + 1))
  done <<< "${entries}"

  [ "${installed}" -gt 0 ] \
    || __warn "No scripts found in scripts/ directory of ${INCUS_GITHUB_OWNER}/${INCUS_GITHUB_REPO}@${INCUS_GITHUB_BRANCH}"
  __ok "${installed} script(s) installed to ${INCUS_SCRIPTS_DEST}/"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__show_summary() {
  local incus_ver
  incus_ver="$(incus --version 2>/dev/null || echo 'installed')"
  __printf_color "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$PRINTF_SET_GREEN"
  __printf_color "  Installation complete" "$PRINTF_SET_GREEN"
  __printf_color "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$PRINTF_SET_GREEN"
  __printf_color "  Incus version    : ${incus_ver}" "$PRINTF_SET_WHITE"
  __printf_color "  Image store      : ${INCUS_SIMPLESTREAMS_DIR}" "$PRINTF_SET_WHITE"
  __printf_color "  Backend          : 127.0.0.1:${INCUS_SIMPLESTREAMS_PORT}" "$PRINTF_SET_WHITE"
  __printf_color "  Registry URL     : http://${INCUS_FQDN}" "$PRINTF_SET_CYAN"
  __printf_color "  Nginx vhost      : ${INCUS_NGINX_CONF_DIR}/${INCUS_FQDN}.conf" "$PRINTF_SET_WHITE"
  __printf_color "  Supported arches : ${INCUS_ARCH}" "$PRINTF_SET_WHITE"
  __printf_color "" ""
  __printf_color "  Add registry as an Incus remote:" "$PRINTF_SET_YELLOW"
  __printf_color "    incus remote add myregistry http://${INCUS_FQDN} --protocol simplestreams" "$PRINTF_SET_WHITE"
  __printf_color "" ""
  __printf_color "  Build and publish images:" "$PRINTF_SET_YELLOW"
  __printf_color "    build-image --help" "$PRINTF_SET_WHITE"
  __printf_color "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" "$PRINTF_SET_GREEN"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__cleanup() { :; }
trap '__cleanup' EXIT ERR
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Parse arguments
_OPTS="$(getopt -o a:vh --long arch:,version,help,no-color,debug -n "${APPNAME}" -- "$@")" || { __help; exit 1; }
eval set -- "${_OPTS}"
while true; do
  case "$1" in
    -a|--arch)
      case "$2" in
        amd64|arm64|both) INCUS_ARCH="$2" ;;
        *) __fatal "--arch must be one of: amd64, arm64, both (got: $2)" ;;
      esac
      shift 2 ;;
    -v|--version) __version;  exit 0 ;;
    -h|--help)    __help;     exit 0 ;;
    --no-color)   NO_COLOR=1; shift ;;
    --debug)      INCUS_DEBUG=1; shift ;;
    --) shift; break ;;
    *)  __fatal "Unknown option: $1" ;;
  esac
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main application
[ "${SET_UID}" -eq 0 ] || __fatal "Must be run as root"

__detect_distro
__install_incus
__configure_incus
__install_incus_simplestreams
__configure_simplestreams
__install_nginx
__configure_nginx
__install_scripts
__show_summary
# - - - - - - - - - - - - - - - - - - - - - - - - -
# End application
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit ${INCUS_EXIT_STATUS}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
