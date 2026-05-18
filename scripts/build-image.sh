#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605172316-git
# @@Author           :  Jason Hempstead
# @@Contact          :  jason@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  build-image.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, May 17, 2026 21:47 EDT
# @@File             :  scripts/build-image.sh
# @@Description      :  Build an Incus container image and publish it to the local SimpleStreams registry
# @@Changelog        :  Add distrobuilder wrapper, SimpleStreams publisher, multi-arch/multi-type build support
# @@TODO             :  Better documentation
# @@Other            :
# @@Resource         :  https://linuxcontainers.org/distrobuilder/
# @@Terminal App     :  no
# @@sudo/root        :  yes
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -
# script variables
APPNAME="${0##*/}"
VERSION="202605172316-git"
RUN_USER="${USER:-root}"
SET_UID="${UID}"
SCRIPT_SRC_DIR="${BASH_SOURCE%/*}"
BUILD_CWD="${PWD}"
BUILD_EXIT_STATUS=0
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
BUILD_ARCH="${BUILD_ARCH:-both}"
BUILD_SIMPLESTREAMS_DIR="${BUILD_SIMPLESTREAMS_DIR:-/var/lib/incus-simplestreams}"
BUILD_SIMPLESTREAMS_PORT="${BUILD_SIMPLESTREAMS_PORT:-8088}"
BUILD_TEMPLATE_DIR="${BUILD_TEMPLATE_DIR:-/var/lib/incus-simplestreams/templates}"
BUILD_TEMPLATE_REPO="${BUILD_TEMPLATE_REPO:-https://raw.githubusercontent.com/lxc/lxc-ci/main/images}"
BUILD_WORK_DIR="${BUILD_WORK_DIR:-${TMPDIR:-/tmp}/casjaysdev-incus-build}"
# container, vm, or both
BUILD_TYPE="${BUILD_TYPE:-container}"
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
Usage: ${APPNAME} [OPTIONS] <distro> <version> [packages]

Build an Incus container image using distrobuilder and publish it
to the local SimpleStreams registry.

Arguments:
  distro      Distribution name (see supported list below)
  version     Version number or codename (e.g. bookworm, 3.21, noble, 9)
  packages    Space-separated list of extra packages to install (quote the list)
              Pass \"\" or omit to install no extras

Options:
  -a, --arch ARCH     Target architecture: amd64, arm64, both (default: both)
  -t, --type TYPE     Image type: container, vm, both (default: container)
  -v, --version       Show version and exit
  -h, --help          Show this help and exit

Environment variables:
  BUILD_SIMPLESTREAMS_DIR   SimpleStreams root (default: /var/lib/incus-simplestreams)
  BUILD_TEMPLATE_DIR        Where to cache distrobuilder YAML templates
  BUILD_WORK_DIR            Temporary build directory
  BUILD_TYPE                Default image type (container/vm/both)

Supported distributions:
  alpine        3.18, 3.19, 3.20, 3.21, edge
  arch          current
  centos        9-stream
  debian        bullseye, bookworm, trixie, sid
  fedora        39, 40, 41, 42
  gentoo        current
  kali          current (rolling)
  mint          21, 22 (vera, virginia, wilma, xia)
  nixos         23.11, 24.05, 24.11
  opensuse      15.5, 15.6, tumbleweed
  oracle        8, 9
  rockylinux    8, 9
  ubuntu        focal, jammy, noble, oracular, plucky
  voidlinux     current

Examples:
  ${APPNAME} debian bookworm
  ${APPNAME} ubuntu noble \"curl git vim\" --arch amd64
  ${APPNAME} alpine 3.21 \"bash curl jq\" --arch arm64
  ${APPNAME} rockylinux 9 \"\" --arch both --type vm
  BUILD_SIMPLESTREAMS_DIR=/mnt/images ${APPNAME} fedora 41 \"podman buildah\"
"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__version() { printf '%s %s\n' "${APPNAME}" "${VERSION}"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Map user-facing distro names to distrobuilder template names and arch labels
# Output: sets __tmpl_name, __tmpl_variant, __arch_label_amd64, __arch_label_arm64
__map_distro() {
  local distro="$1" version="$2"
  __tmpl_name=""
  __tmpl_variant=""
  __arch_label_amd64="amd64"
  __arch_label_arm64="arm64"

  case "${distro}" in
    alpine)
      __tmpl_name="alpine"
      __arch_label_amd64="amd64"
      __arch_label_arm64="arm64"  # distrobuilder normalizes this
      ;;
    arch|archlinux)
      __tmpl_name="archlinux"
      ;;
    centos|centos-stream)
      __tmpl_name="centos"
      __arch_label_arm64="arm64"
      ;;
    debian)
      __tmpl_name="debian"
      ;;
    fedora)
      __tmpl_name="fedora"
      __arch_label_arm64="arm64"
      ;;
    gentoo)
      __tmpl_name="gentoo"
      ;;
    kali)
      __tmpl_name="kali"
      ;;
    mint|linuxmint)
      __tmpl_name="mint"
      ;;
    nixos)
      __tmpl_name="nixos"
      ;;
    opensuse|suse|sles)
      __tmpl_name="opensuse"
      ;;
    oracle|oraclelinux|ol)
      __tmpl_name="oracle"
      __arch_label_arm64="arm64"
      ;;
    rocky|rockylinux)
      __tmpl_name="rockylinux"
      __arch_label_arm64="arm64"
      ;;
    alma|almalinux)
      __tmpl_name="almalinux"
      __arch_label_arm64="arm64"
      ;;
    ubuntu)
      __tmpl_name="ubuntu"
      ;;
    void|voidlinux)
      __tmpl_name="voidlinux"
      ;;
    *)
      # Unknown — try the name as-is; distrobuilder will error if no template
      __tmpl_name="${distro}"
      __warn "Unknown distro '${distro}' — attempting anyway"
      ;;
  esac
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__install_distrobuilder() {
  __step "Checking distrobuilder"
  if __cmd_exists distrobuilder; then
    __ok "distrobuilder already installed ($(distrobuilder --version 2>/dev/null | head -1 || echo '?'))"
    return 0
  fi

  __info "distrobuilder not found — installing"

  # Detect host OS for package install
  local host_arch
  host_arch="$(uname -m)"
  case "${host_arch}" in
    x86_64)  host_arch="amd64" ;;
    aarch64) host_arch="arm64" ;;
    *) __fatal "Unsupported host architecture: ${host_arch}" ;;
  esac

  # Try GitHub release binary first (fastest, no build needed)
  local api_url="https://api.github.com/repos/lxc/distrobuilder/releases/latest"
  local bin_url
  bin_url="$(curl -fsSL "${api_url}" \
    | grep -oE '"browser_download_url": *"[^"]*distrobuilder[^"]*linux[_-]'"${host_arch}"'[^"]*"' \
    | head -1 | cut -d'"' -f4 || true)"

  if [ -n "${bin_url}" ]; then
    __info "Downloading distrobuilder binary"
    local tmpfile
    tmpfile="$(mktemp --suffix=.tar.gz)"
    curl -fsSL "${bin_url}" -o "${tmpfile}"
    tar -xzf "${tmpfile}" -C /usr/local/bin --strip-components=1 'distrobuilder' 2>/dev/null \
      || tar -xzf "${tmpfile}" -C /usr/local/bin distrobuilder 2>/dev/null \
      || (tar -xzf "${tmpfile}" -C /usr/local/bin && chmod +x /usr/local/bin/distrobuilder)
    rm -f "${tmpfile}"
    chmod 755 /usr/local/bin/distrobuilder
    __ok "distrobuilder installed from GitHub release"
    return 0
  fi

  # Fall back to go install
  if __cmd_exists go; then
    __info "Building distrobuilder via go install"
    CGO_ENABLED=0 GOBIN=/usr/local/bin go install \
      github.com/lxc/distrobuilder/distrobuilder@latest
    __ok "distrobuilder built and installed"
    return 0
  fi

  __fatal "Cannot install distrobuilder: no release binary and no go toolchain. Install go or distrobuilder manually."
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__fetch_template() {
  local distro="$1"
  local tmpl_name="$2"
  local tmpl_file="${BUILD_TEMPLATE_DIR}/${tmpl_name}.yaml"

  mkdir -p "${BUILD_TEMPLATE_DIR}"

  if [ -f "${tmpl_file}" ]; then
    __info "Using cached template: ${tmpl_file}"
    printf '%s\n' "${tmpl_file}"
    return 0
  fi

  __info "Fetching template: ${BUILD_TEMPLATE_REPO}/${tmpl_name}.yaml"
  if curl -fsSL "${BUILD_TEMPLATE_REPO}/${tmpl_name}.yaml" -o "${tmpl_file}" 2>/dev/null; then
    __ok "Template cached: ${tmpl_file}"
    printf '%s\n' "${tmpl_file}"
    return 0
  fi

  # Not in lxc-ci — generate a minimal template
  __warn "No upstream template for '${tmpl_name}' — generating minimal template"
  __generate_minimal_template "${distro}" "${tmpl_name}" "${tmpl_file}"
  printf '%s\n' "${tmpl_file}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__generate_minimal_template() {
  local distro="$1" tmpl_name="$2" out="$3"
  # Minimal distrobuilder YAML that covers common distros not in lxc-ci
  cat > "${out}" << EOYAML
image:
  name: ${distro}
  distribution: ${distro}
  release: "{{ image.release }}"
  description: "{{ image.distribution }} {{ image.release }}"
  architecture: "{{ image.architecture }}"

source:
  downloader: ${distro}
  url: ""

packages:
  manager: auto
  update: true
  cleanup: true
  sets:
    - packages:
        - bash
        - ca-certificates
        - curl
      action: install

actions: []

mappings:
  architecture_map: debian
EOYAML
  __warn "Minimal template written — you may need to edit ${out} for this distro"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__inject_packages() {
  local tmpl_file="$1"
  local packages="$2"
  [ -z "${packages}" ] && return 0

  __info "Injecting extra packages into template: ${packages}"
  local tmp
  tmp="$(mktemp --suffix=.yaml)"
  cp "${tmpl_file}" "${tmp}"

  # Use python3 to safely add packages to the YAML
  python3 - "${tmp}" "${packages}" << 'EOPY'
import sys, re

tmpl_file = sys.argv[1]
pkgs = sys.argv[2].split()

with open(tmpl_file) as f:
    content = f.read()

# Find the packages.sets section and append a new set
extra_set = "\n    - packages:\n"
for p in pkgs:
    extra_set += "        - {}\n".format(p)
extra_set += "      action: install\n"

# Insert before the first "actions:" line or at end of packages section
if "actions:" in content:
    content = content.replace("actions:", extra_set + "actions:", 1)
else:
    content += extra_set

with open(tmpl_file, "w") as f:
    f.write(content)
print("  [INFO]  packages injected: {}".format(" ".join(pkgs)))
EOPY
  rm -f "${tmp}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__build_for_arch() {
  local tmpl_file="$1"
  local distro="$2"
  local version="$3"
  local arch="$4"         # amd64 or arm64
  local arch_label="$5"  # distro-specific label (may differ)
  local img_type="$6"    # container or vm
  local out_dir="$7"

  __step "Building ${distro} ${version} ${arch} (${img_type})"

  local build_dir="${out_dir}/${distro}/${version}/${arch}/${img_type}"
  mkdir -p "${build_dir}"

  local db_type
  case "${img_type}" in
    container) db_type="unified" ;;
    vm)        db_type="disk-kvm.img" ;;
    *)         db_type="unified" ;;
  esac

  local db_args=(
    build-incus
    "${tmpl_file}"
    "${build_dir}"
    --type "${db_type}"
    --compression xz
    --timeout 3600
  )

  # Cross-arch: set architecture if not native
  local native_arch
  native_arch="$(uname -m)"
  case "${native_arch}" in x86_64) native_arch="amd64" ;; aarch64) native_arch="arm64" ;; esac
  if [ "${arch}" != "${native_arch}" ]; then
    db_args+=(--arch "${arch_label}")
    # Warn: cross-arch requires binfmt_misc + qemu-user-static on the host
    __warn "Cross-arch build (${arch}) — ensure binfmt_misc and qemu-user-static are set up"
  fi

  # Pass release/version to distrobuilder
  distrobuilder "${db_args[@]}" \
    -o image.release="${version}" \
    -o image.architecture="${arch_label}" \
    2>&1 | while IFS= read -r line; do printf '         %s\n' "${line}"; done

  __ok "Build complete: ${build_dir}"
  printf '%s\n' "${build_dir}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__publish_image() {
  local build_dir="$1"
  local distro="$2"
  local version="$3"
  local arch="$4"
  local img_type="$5"

  __step "Publishing ${distro} ${version} ${arch} ${img_type} to SimpleStreams"

  # Locate built image files
  local lxd_meta lxd_rootfs lxd_disk
  lxd_meta="$(find "${build_dir}" -name "incus.tar.xz" -o -name "lxd.tar.xz" 2>/dev/null | head -1)"
  lxd_rootfs="$(find "${build_dir}" -name "rootfs.squashfs" 2>/dev/null | head -1)"
  lxd_disk="$(find "${build_dir}" -name "*.qcow2" -o -name "disk-kvm.img" 2>/dev/null | head -1)"

  [ -n "${lxd_meta}" ] || __fatal "No incus.tar.xz/lxd.tar.xz found in ${build_dir}"

  # Destination in simplestreams tree
  local today
  today="$(date -u +%Y%m%d_%H%M)"
  local dest_rel="images/${distro}/${version}/${arch}/${img_type}/${today}"
  local dest="${BUILD_SIMPLESTREAMS_DIR}/${dest_rel}"
  mkdir -p "${dest}"

  __info "Copying image files to ${dest}"
  cp "${lxd_meta}" "${dest}/incus.tar.xz"

  case "${img_type}" in
    container)
      [ -n "${lxd_rootfs}" ] || __fatal "No rootfs.squashfs found for container image"
      cp "${lxd_rootfs}" "${dest}/rootfs.squashfs"
      ;;
    vm)
      [ -n "${lxd_disk}" ] || __fatal "No disk image found for VM image"
      cp "${lxd_disk}" "${dest}/disk.qcow2"
      ;;
  esac

  # Compute SHA-256 fingerprints
  local meta_sha rootfs_sha combined_sha
  meta_sha="$(sha256sum "${dest}/incus.tar.xz" | cut -d' ' -f1)"

  if [ "${img_type}" = "container" ]; then
    rootfs_sha="$(sha256sum "${dest}/rootfs.squashfs" | cut -d' ' -f1)"
    combined_sha="$(cat "${dest}/incus.tar.xz" "${dest}/rootfs.squashfs" | sha256sum | cut -d' ' -f1)"
  else
    rootfs_sha="$(sha256sum "${dest}/disk.qcow2" | cut -d' ' -f1)"
    combined_sha="$(cat "${dest}/incus.tar.xz" "${dest}/disk.qcow2" | sha256sum | cut -d' ' -f1)"
  fi

  # Use incus-simplestreams add if available; otherwise update index manually
  if __cmd_exists incus-simplestreams; then
    __info "Registering image with incus-simplestreams"
    incus-simplestreams add \
      --dir "${BUILD_SIMPLESTREAMS_DIR}" \
      "${distro}/${version}/${arch}/${img_type}" \
      "${dest_rel}/incus.tar.xz" \
      "${combined_sha}" \
      2>/dev/null || __update_index_manual \
        "${distro}" "${version}" "${arch}" "${img_type}" \
        "${today}" "${dest_rel}" "${combined_sha}" "${meta_sha}" "${rootfs_sha}"
  else
    __update_index_manual \
      "${distro}" "${version}" "${arch}" "${img_type}" \
      "${today}" "${dest_rel}" "${combined_sha}" "${meta_sha}" "${rootfs_sha}"
  fi

  __ok "Published: ${distro}/${version}/${arch}/${img_type}"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__update_index_manual() {
  local distro="$1" version="$2" arch="$3" img_type="$4"
  local timestamp="$5" dest_rel="$6" combined_sha="$7" meta_sha="$8" rootfs_sha="$9"

  __info "Updating streams/v1/images.json"
  local index_file="${BUILD_SIMPLESTREAMS_DIR}/streams/v1/images.json"
  local updated
  updated="$(date -u +%a, %d %b %Y %H:%M:%S +0000)"

  local product_key="${distro}:${version}:${arch}:${img_type}"

  # Determine file entries
  local ftype fpath fsha fsize
  if [ "${img_type}" = "container" ]; then
    ftype="squashfs"
    fpath="${dest_rel}/rootfs.squashfs"
    fsha="${rootfs_sha}"
    fsize="$(stat -c%s "${BUILD_SIMPLESTREAMS_DIR}/${dest_rel}/rootfs.squashfs")"
  else
    ftype="disk-kvm.img"
    fpath="${dest_rel}/disk.qcow2"
    fsha="${rootfs_sha}"
    fsize="$(stat -c%s "${BUILD_SIMPLESTREAMS_DIR}/${dest_rel}/disk.qcow2")"
  fi
  local meta_size
  meta_size="$(stat -c%s "${BUILD_SIMPLESTREAMS_DIR}/${dest_rel}/incus.tar.xz")"

  # Use python3 to update the JSON safely
  python3 - \
    "${index_file}" \
    "${product_key}" \
    "${distro}" "${version}" "${arch}" "${img_type}" \
    "${timestamp}" "${updated}" "${combined_sha}" \
    "${dest_rel}/incus.tar.xz" "${meta_sha}" "${meta_size}" \
    "${fpath}" "${fsha}" "${fsize}" "${ftype}" \
    << 'EOPY'
import sys, json, time

idx_file = sys.argv[1]
product_key = sys.argv[2]
distro, version, arch, img_type = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
timestamp, updated, combined_sha = sys.argv[7], sys.argv[8], sys.argv[9]
meta_path, meta_sha, meta_size = sys.argv[10], sys.argv[11], int(sys.argv[12])
fpath, fsha, fsize, ftype = sys.argv[13], sys.argv[14], int(sys.argv[15]), sys.argv[16]

with open(idx_file) as f:
    data = json.load(f)

products = data.setdefault("products", {})
product = products.setdefault(product_key, {
    "aliases": "{}/{}".format(distro, version),
    "arch": arch,
    "os": distro,
    "release": version,
    "release_title": "{} {}".format(distro.capitalize(), version),
    "versions": {}
})

product["versions"][timestamp] = {
    "items": {
        "incus.tar.xz": {
            "combined_sha256": combined_sha,
            "ftype": "incus.tar.xz",
            "path": meta_path,
            "sha256": meta_sha,
            "size": meta_size
        },
        ftype: {
            "combined_sha256": combined_sha,
            "ftype": ftype,
            "path": fpath,
            "sha256": fsha,
            "size": fsize
        }
    }
}
data["updated"] = updated

with open(idx_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  [ OK ]  images.json updated")
EOPY

  # Also patch the index.json updated timestamp
  local top_index="${BUILD_SIMPLESTREAMS_DIR}/streams/v1/index.json"
  if [ -f "${top_index}" ]; then
    python3 - "${top_index}" "${updated}" << 'EOPY'
import sys, json
idx_file, updated = sys.argv[1], sys.argv[2]
with open(idx_file) as f:
    data = json.load(f)
for v in data.get("index", {}).values():
    v["updated"] = updated
with open(idx_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
EOPY
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__reload_simplestreams() {
  # Bump the backend so nginx cache sees fresh JSON
  if __cmd_exists systemctl && systemctl is-active incus-simplestreams.service >/dev/null 2>&1; then
    systemctl reload-or-restart incus-simplestreams.service 2>/dev/null || true
    __ok "SimpleStreams service reloaded"
  elif __cmd_exists rc-service && rc-service incus-simplestreams status >/dev/null 2>&1; then
    rc-service incus-simplestreams restart 2>/dev/null || true
    __ok "SimpleStreams service restarted"
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__cleanup() {
  [ -n "${BUILD_WORK_DIR:-}" ] && [ -d "${BUILD_WORK_DIR}" ] && rm -rf "${BUILD_WORK_DIR}"
}
trap '__cleanup' EXIT ERR
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Parse arguments
PARSED="$(getopt -o a:t:vh --long arch:,type:,version,help,no-color,debug -n "${APPNAME}" -- "$@")" || {
  __help; exit 1
}
eval set -- "${PARSED}"
while true; do
  case "$1" in
    -a|--arch)
      case "$2" in
        amd64|arm64|both) BUILD_ARCH="$2" ;;
        *) __fatal "--arch must be one of: amd64, arm64, both (got: $2)" ;;
      esac
      shift 2 ;;
    -t|--type)
      case "$2" in
        container|vm|both) BUILD_TYPE="$2" ;;
        *) __fatal "--type must be one of: container, vm, both (got: $2)" ;;
      esac
      shift 2 ;;
    -v|--version) __version;  exit 0 ;;
    -h|--help)    __help;     exit 0 ;;
    --no-color)   NO_COLOR=1; shift ;;
    --debug)      BUILD_DEBUG=1; shift ;;
    --) shift; break ;;
    *)  __fatal "Unknown option: $1" ;;
  esac
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main application
[ "${SET_UID}" -eq 0 ] || __fatal "Must be run as root"

# Positional args
DISTRO="${1:-}"
VERSION="${2:-}"
EXTRA_PKGS="${3:-}"

[ -n "${DISTRO}" ]  || { __error "Missing required argument: distro";   __help; exit 1; }
[ -n "${VERSION}" ] || { __error "Missing required argument: version"; __help; exit 1; }

__info "Distro   : ${DISTRO}"
__info "Version  : ${VERSION}"
__info "Packages : ${EXTRA_PKGS:-<none>}"
__info "Arch     : ${BUILD_ARCH}"
__info "Type     : ${BUILD_TYPE}"

__install_distrobuilder

# Map distro to template name and arch labels
__map_distro "${DISTRO}" "${VERSION}"
TMPL_NAME="${__tmpl_name}"

# Fetch/cache the distrobuilder YAML template
TMPL_FILE="$(__fetch_template "${DISTRO}" "${TMPL_NAME}")"

# Inject extra packages into a working copy
if [ -n "${EXTRA_PKGS}" ]; then
  WORK_TMPL="${BUILD_WORK_DIR}/$(basename "${TMPL_FILE}")"
  mkdir -p "${BUILD_WORK_DIR}"
  cp "${TMPL_FILE}" "${WORK_TMPL}"
  __inject_packages "${WORK_TMPL}" "${EXTRA_PKGS}"
  TMPL_FILE="${WORK_TMPL}"
fi

# Determine arch list to build
ARCHES=()
case "${BUILD_ARCH}" in
  amd64) ARCHES=("amd64") ;;
  arm64) ARCHES=("arm64") ;;
  both)  ARCHES=("amd64" "arm64") ;;
esac

# Determine image type list
TYPES=()
case "${BUILD_TYPE}" in
  container) TYPES=("container") ;;
  vm)        TYPES=("vm") ;;
  both)      TYPES=("container" "vm") ;;
esac

# Build + publish
for arch in "${ARCHES[@]}"; do
  # Pick the distro-specific arch label
  case "${arch}" in
    amd64) arch_label="${__arch_label_amd64}" ;;
    arm64) arch_label="${__arch_label_arm64}" ;;
  esac

  for img_type in "${TYPES[@]}"; do
    build_out_dir="${BUILD_WORK_DIR}/output/${DISTRO}/${VERSION}"
    mkdir -p "${build_out_dir}"

    built_dir="$(__build_for_arch \
      "${TMPL_FILE}" "${DISTRO}" "${VERSION}" \
      "${arch}" "${arch_label}" "${img_type}" "${build_out_dir}")"

    __publish_image "${built_dir}" "${DISTRO}" "${VERSION}" "${arch}" "${img_type}"
  done
done

__reload_simplestreams

__printf_color "\n  Build and publish complete." "$PRINTF_SET_GREEN"
__printf_color "  List images: incus image list myregistry:" "$PRINTF_SET_CYAN"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# End application
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit ${BUILD_EXIT_STATUS}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
