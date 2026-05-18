# incus

Install and configure [Incus](https://linuxcontainers.org/incus/) on any major Linux distribution, spin up a [SimpleStreams](https://linuxcontainers.org/incus/docs/main/reference/remote_image_servers/) image registry backed by Nginx, and build custom distro images with `distrobuilder` — all non-interactively and idempotently.

---

## 📦 Install

Run as root on the target machine. The script auto-detects the host distribution and handles everything.

```bash
curl -LSsf https://raw.githubusercontent.com/scriptmgr/incus/main/install.sh \
  | bash
```

Or clone and run locally:

```bash
git clone https://github.com/scriptmgr/incus.git
cd incus
bash install.sh
```

### What it does

1. **Detects your distro** — Debian, Ubuntu, Fedora, RHEL, Rocky, Alma, CentOS, Arch, openSUSE, Alpine, and ~40 derivatives
2. **Installs Incus** from the upstream repo for your distro family (zabbly / COPR / AUR / OBS / apk)
3. **Initialises Incus** (`incus admin init --auto`) — skipped if already done
4. **Installs `incus-simplestreams`** — package manager → GitHub release binary → `go install`
5. **Creates a SimpleStreams image server** — `python3 -m http.server` systemd/OpenRC service on `127.0.0.1:8088`
6. **Installs Nginx** and writes `/etc/nginx/vhosts.d/{fqdn}.conf` as a reverse proxy to the image server
7. **Downloads all scripts** from [`scripts/`](scripts/) via GitHub API and installs them to `/usr/local/bin/`

### Supported distributions

| Family | Distros |
|--------|---------|
| Debian / Ubuntu | Debian, Ubuntu, Mint, Pop!_OS, Elementary, Kali, Parrot, Raspbian, MX, Zorin, neon, Devuan, and more |
| Fedora | Fedora, Nobara, Ultramarine, Bazzite, Silverblue |
| RHEL | RHEL, CentOS Stream, Rocky Linux, AlmaLinux, Oracle Linux, CloudLinux |
| Arch | Arch, Manjaro, EndeavourOS, Garuda, Artix, CachyOS |
| SUSE | openSUSE Tumbleweed, openSUSE Leap, MicroOS, SLES |
| Alpine | Alpine Linux |

### Options

```
install.sh [OPTIONS]

  -a, --arch ARCH     Architectures to support: amd64, arm64, both (default: both)
  -v, --version       Show version and exit
  -h, --help          Show this help and exit
```

### Environment overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `INCUS_FQDN` | `hostname --fqdn` | Registry hostname for Nginx vhost |
| `INCUS_SIMPLESTREAMS_PORT` | `8088` | Backend HTTP port |
| `INCUS_SIMPLESTREAMS_DIR` | `/var/lib/incus-simplestreams` | Image storage root |
| `INCUS_SIMPLESTREAMS_USER` | `incus-streams` | Service user |
| `INCUS_NGINX_CONF_DIR` | `/etc/nginx/vhosts.d` | Nginx vhost config directory |
| `INCUS_GITHUB_OWNER` | `scriptmgr` | GitHub org for script downloads |
| `INCUS_GITHUB_REPO` | `incus` | GitHub repo for script downloads |
| `INCUS_GITHUB_BRANCH` | `main` | Branch to pull scripts from |
| `INCUS_SCRIPTS_DEST` | `/usr/local/bin` | Install destination for scripts |
| `GITHUB_TOKEN` | _(unset)_ | Optional token for private repos / rate-limit bypass |

```bash
# Example: custom FQDN and port
INCUS_FQDN=images.example.com INCUS_SIMPLESTREAMS_PORT=9000 bash install.sh
```

### Add the registry as an Incus remote

After install, add your registry on any Incus host:

```bash
incus remote add myregistry http://images.example.com --protocol simplestreams
incus image list myregistry:
```

---

## 🖼️ Building Images

`build-image` is installed to `/usr/local/bin/` by the installer. It builds container or VM images using [`distrobuilder`](https://linuxcontainers.org/distrobuilder/) and publishes them directly to your SimpleStreams registry.

```
build-image [OPTIONS] <distro> <version> [packages]

  -a, --arch ARCH     Target architecture: amd64, arm64, both (default: both)
  -t, --type TYPE     Image type: container, vm, both (default: container)
  -v, --version       Show version and exit
  -h, --help          Show this help and exit
```

### Examples

```bash
# Debian Bookworm container, both arches
build-image debian bookworm

# Ubuntu Noble with extra packages, amd64 only
build-image ubuntu noble "curl git vim" --arch amd64

# Alpine 3.21 container, arm64 only
build-image alpine 3.21 "bash curl jq" --arch arm64

# Rocky Linux 9 VM image, both arches
build-image rockylinux 9 "" --arch both --type vm

# Fedora 41 with custom packages
build-image fedora 41 "podman buildah skopeo"
```

### Supported distros for building

`alpine` · `arch` · `centos` · `debian` · `fedora` · `gentoo` · `kali` · `mint` · `nixos` · `opensuse` · `oracle` · `rockylinux` · `almalinux` · `ubuntu` · `voidlinux`

Templates are fetched from the [lxc-ci](https://github.com/lxc/lxc-ci/tree/main/images) repository and cached locally. A minimal template is generated for distros not found upstream.

> **Cross-arch builds** (e.g. building arm64 on an amd64 host) require `binfmt_misc` and `qemu-user-static` set up on the host.

---

## 🛠️ Development

The project is two shell scripts. No build step required.

```bash
git clone https://github.com/scriptmgr/incus.git
cd incus

# Syntax-check
bash -n install.sh
bash -n scripts/build-image.sh

# Test help output
bash install.sh --help
bash scripts/build-image.sh --help
```

### Files

| Path | Purpose |
|------|---------|
| `install.sh` | Main installer — distro detection, Incus, SimpleStreams, Nginx, script deployment |
| `scripts/build-image.sh` | Image builder — distrobuilder wrapper, SimpleStreams publisher |

---

## 📄 License

WTFPL — see [LICENSE.md](LICENSE.md)
