#!/usr/bin/env bash
# =============================================================================
#  EQUINOX INSTALLER  -  pemasang Linux Terminal Equinox (Termux & Linux)
#
#  Pemakaian:
#     ./Installer.sh                 pasang / perbarui (interaktif)
#     ./Installer.sh --yes           tanpa pertanyaan (otomatis setuju pasang dependensi)
#     ./Installer.sh --full          sekaligus pasang paket tambahan (nano, jq, tree, ...)
#     ./Installer.sh --autostart     buka Equinox otomatis tiap Termux dibuka
#     ./Installer.sh --update        perbarui file inti (konfigurasi dipertahankan)
#     ./Installer.sh --uninstall     copot Equinox (--purge: hapus juga data ~/.equinox)
#     ./Installer.sh --check         hanya periksa kesiapan sistem, tanpa mengubah apa pun
#     ./Installer.sh --help          bantuan lengkap
#
#  Yang dilakukan:
#     1. Deteksi lingkungan (Termux / Linux, package manager, prefix)
#     2. Pemeriksaan awal (versi bash, ruang disk, hak tulis, koneksi)
#     3. Memasang dependensi yang kurang
#     4. Mencari equinox-core.sh (lokal, atau unduh dari GitHub bila tidak ada)
#     5. Memvalidasi inti (sintaks), membackup instalasi lama, menyalin file
#     6. Membuat perintah `equinox` dan `eqx`, metadata, dan konfigurasi awal
#     7. (Opsional) autostart di ~/.bashrc
#     8. Uji verifikasi akhir (sintaks, peluncur, selftest)
# =============================================================================

# Pastikan dijalankan oleh bash (mis. jika dipanggil dengan `sh Installer.sh`)
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "Installer ini membutuhkan bash. Pasang dulu: pkg install bash" >&2
  exit 1
fi

set -uo pipefail

# -----------------------------------------------------------------------------
# Konstanta
# -----------------------------------------------------------------------------
INSTALLER_VERSION="1.0.0"
APP_NAME="Equinox"
CORE_NAME="equinox-core.sh"
REPO_URL="https://github.com/zalqi-1113/Equinox-Linux-Terminal-"
RAW_URL="https://raw.githubusercontent.com/zalqi-1113/Equinox-Linux-Terminal-"
BRANCHES=(main master)
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
DATA_DIR="${EQX_HOME:-$HOME/.equinox}"
MARK_AUTO_BEGIN="# >>> equinox autostart >>>"
MARK_AUTO_END="# <<< equinox autostart <<<"
MARK_PATH_BEGIN="# >>> equinox path >>>"
MARK_PATH_END="# <<< equinox path <<<"

# Perintah wajib yang diperlukan inti Equinox
REQUIRED_CMDS=(bash curl awk sed grep find tar gzip tput ps timeout date sort mktemp cut tr wc head tail df du base64 md5sum cat chmod cp mv ln)

# -----------------------------------------------------------------------------
# Opsi
# -----------------------------------------------------------------------------
ASSUME_YES=0
MODE="install"          # install | update | uninstall | check
DO_DEPS=1
AUTOSTART="ask"         # ask | yes | no
PURGE=0
FULL=0
OFFLINE=0
FORCE_DOWNLOAD=0
PREFIX_OVERRIDE=""
CORE_SRC=""
CORE_TMP=""
FAILED=0
TOTAL_STEPS=7
STEP_NO=0

# -----------------------------------------------------------------------------
# Tampilan
# -----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_R=$'\e[0m'; C_B=$'\e[1m'; C_D=$'\e[2m'
  C_P=$'\e[38;5;39m'; C_A=$'\e[38;5;141m'; C_OK=$'\e[38;5;78m'; C_W=$'\e[38;5;221m'; C_E=$'\e[38;5;203m'
else
  C_R=""; C_B=""; C_D=""; C_P=""; C_A=""; C_OK=""; C_W=""; C_E=""
fi

LOGDIR="$DATA_DIR/logs"
mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR="${TMPDIR:-/tmp}"
LOGFILE="$LOGDIR/install-$STAMP.log"
: >"$LOGFILE" 2>/dev/null || LOGFILE="/dev/null"

log()  { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOGFILE" 2>/dev/null; return 0; }
info() { printf '  %s●%s %s\n' "$C_P" "$C_R" "$*"; log "INFO $*"; }
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_R" "$*"; log "OK   $*"; }
warn() { printf '  %s▲%s %s\n' "$C_W" "$C_R" "$*" >&2; log "WARN $*"; }
err()  { printf '  %s✘%s %s\n' "$C_E" "$C_R" "$*" >&2; log "ERR  $*"; }
dim()  { printf '  %s%s%s\n' "$C_D" "$*" "$C_R"; }
step() { STEP_NO=$(( STEP_NO + 1 )); printf '\n%s[%d/%d]%s %s%s%s\n' "$C_A" "$STEP_NO" "$TOTAL_STEPS" "$C_R" "$C_B" "$*" "$C_R"; log "STEP $*"; }

die() {
  FAILED=1
  err "$*"
  printf '\n  %sInstalasi dihentikan.%s Log lengkap: %s\n' "$C_E" "$C_R" "$LOGFILE" >&2
  if [ -s "$LOGFILE" ] && [ "$LOGFILE" != "/dev/null" ]; then
    printf '  %s--- 12 baris terakhir log ---%s\n' "$C_D" "$C_R" >&2
    tail -n 12 "$LOGFILE" 2>/dev/null | sed 's/^/    /' >&2
  fi
  exit 1
}

banner() {
  printf '%s' "$C_P"
  cat <<'EOF'
 ___    ___    _   _   ___   _  _    ___   __  __
| __|  / _ \  | | | | |_ _| | \| |  / _ \  \ \/ /
| _|  | (_) | | |_| |  | |  | .` | | (_) |  >  < 
|___|  \__\_\  \___/  |___| |_|\_|  \___/  /_/\_\
EOF
  printf '%s' "$C_R"
  printf '  %sInstaller v%s  -  Linux Terminal untuk Termux%s\n' "$C_D" "$INSTALLER_VERSION" "$C_R"
}

have() { command -v "$1" >/dev/null 2>&1; }

on_exit() {
  [ -n "$CORE_TMP" ] && rm -f "$CORE_TMP" 2>/dev/null
  return 0
}
trap on_exit EXIT
trap 'printf "\n"; err "Dibatalkan oleh pengguna."; exit 130' INT TERM

usage() {
  cat <<EOF
Equinox Installer v$INSTALLER_VERSION

Pemakaian: ./Installer.sh [opsi]

Opsi:
  -y, --yes           Jawab "ya" untuk pemasangan dependensi (tanpa pertanyaan)
      --full          Pasang juga paket tambahan (nano, jq, tree, openssl, termux-api)
      --autostart     Aktifkan Equinox otomatis saat shell dibuka
      --no-autostart  Jangan tanya/aktifkan autostart
      --update        Perbarui file inti saja (konfigurasi tetap)
      --uninstall     Copot Equinox
      --purge         Dengan --uninstall: hapus juga data di $DATA_DIR
      --check         Periksa kesiapan sistem saja
      --no-deps       Lewati pemasangan dependensi
      --offline       Jangan unduh dari GitHub (wajib ada $CORE_NAME lokal)
      --download      Paksa unduh inti terbaru dari GitHub
      --prefix DIR    Pasang ke DIR (bin/ dan lib/equinox/ di dalamnya)
  -v, --version       Tampilkan versi installer
  -h, --help          Bantuan ini

Contoh:
  ./Installer.sh
  ./Installer.sh --yes --full --autostart
  ./Installer.sh --update
  ./Installer.sh --uninstall --purge

Repo: $REPO_URL
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) ASSUME_YES=1 ;;
      --full) FULL=1 ;;
      --autostart) AUTOSTART="yes" ;;
      --no-autostart) AUTOSTART="no" ;;
      --update) MODE="update" ;;
      --uninstall|--remove) MODE="uninstall" ;;
      --purge) PURGE=1 ;;
      --check) MODE="check" ;;
      --no-deps) DO_DEPS=0 ;;
      --offline) OFFLINE=1 ;;
      --download) FORCE_DOWNLOAD=1 ;;
      --prefix)
        [ $# -ge 2 ] || { echo "Opsi --prefix membutuhkan nilai" >&2; exit 2; }
        PREFIX_OVERRIDE="$2"; shift ;;
      --prefix=*) PREFIX_OVERRIDE="${1#--prefix=}" ;;
      -v|--version) echo "Equinox Installer $INSTALLER_VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Opsi tidak dikenal: $1 (lihat --help)" >&2; exit 2 ;;
    esac
    shift
  done
}

# Tanya ya/tidak. $1 = pertanyaan, $2 = default (y|n), $3 = "honor-yes" bila --yes berlaku
ask_yn() {
  local q="$1" def="${2:-n}" honor="${3:-}" ans hint
  [ "$def" = "y" ] && hint="Y/n" || hint="y/N"
  if [ "$honor" = "honor-yes" ] && [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ ! -t 0 ]; then [ "$def" = "y" ]; return; fi
  read -r -p "  ${C_W}?${C_R} $q [$hint] " ans || return 1
  ans="${ans:-$def}"
  case "$ans" in y|Y|ya|YA|Ya|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Jalankan perintah dengan spinner; output masuk log. $1 = deskripsi
run_step() {
  local desc="$1"; shift
  local pid rc i=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  log "RUN  $*"
  if [ -n "${SUDO:-}" ] && [ "${1:-}" = "$SUDO" ]; then
    # sudo mungkin meminta password -> jalankan di foreground
    info "$desc"
    "$@" 2>&1 | tee -a "$LOGFILE"
    rc=${PIPESTATUS[0]}
  else
    "$@" >>"$LOGFILE" 2>&1 </dev/null &
    pid=$!
    if [ -t 1 ]; then
      while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s %s' "$C_P" "${frames[i % ${#frames[@]}]}" "$C_R" "$desc"
        i=$(( i + 1 )); sleep 0.1
      done
      printf '\r\033[K'
    fi
    wait "$pid"; rc=$?
  fi
  if [ "$rc" -eq 0 ]; then ok "$desc"; else err "$desc (kode keluar $rc)"; fi
  return "$rc"
}

# -----------------------------------------------------------------------------
# 1. Deteksi lingkungan
# -----------------------------------------------------------------------------
detect_env() {
  IS_TERMUX=0
  if [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *com.termux* ]] || [ -d /data/data/com.termux/files/usr ]; then
    IS_TERMUX=1
  fi
  ARCH="$(uname -m 2>/dev/null || echo unknown)"
  BASH_BIN="$(command -v bash 2>/dev/null || true)"
  [ -n "$BASH_BIN" ] || BASH_BIN="${BASH:-/bin/bash}"

  PKGMGR="none"
  if [ "$IS_TERMUX" -eq 1 ] && have pkg; then PKGMGR="pkg"
  elif have apt-get; then PKGMGR="apt"
  elif have dnf; then PKGMGR="dnf"
  elif have pacman; then PKGMGR="pacman"
  elif have apk; then PKGMGR="apk"
  elif have zypper; then PKGMGR="zypper"
  fi

  SUDO=""
  if [ "$(id -u 2>/dev/null || echo 1)" -ne 0 ] && [ "$IS_TERMUX" -eq 0 ] && have sudo; then SUDO="sudo"; fi

  if [ -n "$PREFIX_OVERRIDE" ]; then INSTALL_PREFIX="$PREFIX_OVERRIDE"
  elif [ "$IS_TERMUX" -eq 1 ]; then INSTALL_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
  elif [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then INSTALL_PREFIX="/usr/local"
  else INSTALL_PREFIX="$HOME/.local"; fi
  BIN_DIR="$INSTALL_PREFIX/bin"
  LIB_DIR="$INSTALL_PREFIX/lib/equinox"
  LAUNCHER="$BIN_DIR/equinox"
  LAUNCHER_ALIAS="$BIN_DIR/eqx"

  if [ "$IS_TERMUX" -eq 1 ] && have getprop; then
    OS_NAME="Android $(getprop ro.build.version.release 2>/dev/null) (Termux)"
  elif [ -r /etc/os-release ]; then
    OS_NAME="$( . /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}" )"
  else
    OS_NAME="$(uname -s 2>/dev/null)"
  fi
  log "env: termux=$IS_TERMUX arch=$ARCH pkgmgr=$PKGMGR prefix=$INSTALL_PREFIX bash=$BASH_BIN os=$OS_NAME"
}

# -----------------------------------------------------------------------------
# 2. Pemeriksaan awal
# -----------------------------------------------------------------------------
preflight() {
  local free_kb
  info "Sistem     : $OS_NAME ($ARCH)"
  info "Bash       : $BASH_VERSION  ($BASH_BIN)"
  info "Pkg manager: $PKGMGR"
  info "Prefix     : $INSTALL_PREFIX"

  if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2 ) )); then
    die "Bash $BASH_VERSION terlalu lama. Equinox membutuhkan Bash 4.2+. Perbarui: pkg install bash"
  fi
  ok "Versi bash memadai"

  if ! mkdir -p "$DATA_DIR" 2>/dev/null || [ ! -w "$DATA_DIR" ]; then
    die "Tidak dapat menulis ke $DATA_DIR"
  fi
  ok "Folder data dapat ditulis: $DATA_DIR"

  mkdir -p "$BIN_DIR" "$LIB_DIR" 2>/dev/null || true
  if [ ! -w "$BIN_DIR" ] || [ ! -w "$LIB_DIR" ]; then
    if [ "$IS_TERMUX" -eq 1 ]; then
      die "Tidak dapat menulis ke $INSTALL_PREFIX (cek instalasi Termux Anda)"
    else
      die "Tidak dapat menulis ke $INSTALL_PREFIX. Jalankan sebagai root atau pakai: --prefix \$HOME/.local"
    fi
  fi
  ok "Lokasi pemasangan dapat ditulis"

  free_kb="$(df -Pk "$INSTALL_PREFIX" 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "${free_kb:-}" ] && [ "$free_kb" -lt 30720 ] 2>/dev/null; then
    die "Ruang disk kurang (tersisa $(( free_kb / 1024 )) MB, butuh minimal 30 MB)"
  fi
  [ -n "${free_kb:-}" ] && ok "Ruang disk: $(( free_kb / 1024 )) MB tersedia"

  if have curl; then
    if curl -fsS --max-time 8 -o /dev/null https://github.com 2>>"$LOGFILE"; then
      NET_OK=1; ok "Koneksi internet tersedia"
    else
      NET_OK=0; warn "Internet tidak terjangkau (instalasi lokal tetap bisa, pemasangan paket mungkin gagal)"
    fi
  else
    NET_OK=0
  fi
}

# -----------------------------------------------------------------------------
# 3. Dependensi
# -----------------------------------------------------------------------------
pkg_for() { # perintah -> nama paket menurut package manager
  case "$1" in
    awk) echo gawk ;;
    tput) case "$PKGMGR" in pkg) echo ncurses-utils ;; apt) echo ncurses-bin ;; *) echo ncurses ;; esac ;;
    ps) case "$PKGMGR" in dnf|pacman) echo procps-ng ;; *) echo procps ;; esac ;;
    find) echo findutils ;;
    sed) echo sed ;; grep) echo grep ;; tar) echo tar ;; gzip) echo gzip ;;
    curl) echo curl ;; bash) echo bash ;; git) echo git ;;
    *) echo coreutils ;;
  esac
}

pm_update() {
  case "$PKGMGR" in
    pkg)    pkg update -y ;;
    apt)    ${SUDO:+$SUDO} apt-get update ;;
    dnf)    ${SUDO:+$SUDO} dnf makecache ;;
    pacman) ${SUDO:+$SUDO} pacman -Sy --noconfirm ;;
    apk)    ${SUDO:+$SUDO} apk update ;;
    zypper) ${SUDO:+$SUDO} zypper refresh ;;
    *) return 1 ;;
  esac
}

pm_install() {
  case "$PKGMGR" in
    pkg)    pkg install -y "$@" ;;
    apt)    ${SUDO:+$SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    ${SUDO:+$SUDO} dnf install -y "$@" ;;
    pacman) ${SUDO:+$SUDO} pacman -S --noconfirm --needed "$@" ;;
    apk)    ${SUDO:+$SUDO} apk add "$@" ;;
    zypper) ${SUDO:+$SUDO} zypper install -y "$@" ;;
    *) return 1 ;;
  esac
}

install_deps() {
  local c missing=() pkgs=() list
  for c in "${REQUIRED_CMDS[@]}"; do have "$c" || missing+=("$c"); done

  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Perintah wajib belum ada: ${missing[*]}"
    for c in "${missing[@]}"; do pkgs+=("$(pkg_for "$c")"); done
  else
    ok "Semua perintah wajib sudah tersedia"
  fi

  if [ "$FULL" -eq 1 ]; then
    pkgs+=(nano jq tree)
    if [ "$IS_TERMUX" -eq 1 ]; then pkgs+=(openssl-tool termux-api git zip unzip)
    else pkgs+=(openssl git zip unzip); fi
  elif [ "$IS_TERMUX" -eq 0 ] || [ "${#missing[@]}" -eq 0 ]; then
    :
  fi

  if [ "${#pkgs[@]}" -eq 0 ]; then return 0; fi
  list="$(printf '%s\n' "${pkgs[@]}" | sort -u | tr '\n' ' ')"
  list="${list% }"

  if [ "$DO_DEPS" -eq 0 ]; then
    warn "Pemasangan dependensi dilewati (--no-deps). Paket yang disarankan: $list"
    return 0
  fi
  if [ "$PKGMGR" = "none" ]; then
    [ "${#missing[@]}" -eq 0 ] && return 0
    die "Package manager tidak ditemukan. Pasang manual: ${missing[*]}"
  fi
  if [ "$IS_TERMUX" -eq 0 ] && [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
    [ "${#missing[@]}" -eq 0 ] && return 0
    die "Butuh root/sudo untuk memasang: $list"
  fi

  if ! ask_yn "Pasang paket: $list ?" y honor-yes; then
    [ "${#missing[@]}" -eq 0 ] && { info "Paket tambahan dilewati"; return 0; }
    die "Dependensi wajib tidak dipasang: ${missing[*]}"
  fi

  # shellcheck disable=SC2086
  if ! run_step "Memasang paket: $list" pm_install $list; then
    warn "Gagal. Memperbarui indeks paket lalu mencoba lagi..."
    run_step "Memperbarui indeks paket" pm_update || true
    # shellcheck disable=SC2086
    run_step "Memasang ulang: $list" pm_install $list || warn "Sebagian paket gagal dipasang (lihat log)"
  fi

  hash -r 2>/dev/null
  missing=()
  for c in "${REQUIRED_CMDS[@]}"; do have "$c" || missing+=("$c"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    if [ "$IS_TERMUX" -eq 1 ]; then
      die "Masih ada perintah yang hilang: ${missing[*]}. Coba: termux-change-repo, lalu pkg update, lalu jalankan ulang installer."
    fi
    die "Masih ada perintah yang hilang: ${missing[*]}"
  fi
  ok "Dependensi wajib terpenuhi"
}

# -----------------------------------------------------------------------------
# 4. Mencari / mengunduh inti
# -----------------------------------------------------------------------------
validate_core() { # file
  local f="$1"
  [ -s "$f" ] || return 1
  [ "$(head -c 2 "$f" 2>/dev/null)" = "#!" ] || return 1
  grep -q 'EQX_CORE_LOADED' "$f" 2>/dev/null || return 1
  bash -n "$f" 2>>"$LOGFILE" || return 1
  return 0
}

download_core() {
  have curl || return 1
  local b url tmp
  tmp="$(mktemp 2>/dev/null)" || tmp="$DATA_DIR/cache-core.$$"
  for b in "${BRANCHES[@]}"; do
    url="$RAW_URL/$b/$CORE_NAME"
    log "unduh: $url"
    if curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 -o "$tmp" "$url" 2>>"$LOGFILE"; then
      if validate_core "$tmp"; then CORE_SRC="$tmp"; CORE_TMP="$tmp"; ok "Inti diunduh dari GitHub (branch $b)"; return 0; fi
      warn "Berkas dari branch $b tidak valid"
    fi
  done
  rm -f "$tmp"
  return 1
}

find_core() {
  local cand
  CORE_SRC=""
  # Jika installer dijalankan dari folder instalasi sendiri, inti lokal = versi terpasang -> unduh baru
  if [ "$SCRIPT_DIR" = "$LIB_DIR" ]; then FORCE_DOWNLOAD=1; fi

  if [ "$FORCE_DOWNLOAD" -eq 0 ]; then
    for cand in "$SCRIPT_DIR/$CORE_NAME" "$SCRIPT_DIR"/*[Cc]ore*.sh "$SCRIPT_DIR"/core/*.sh "$SCRIPT_DIR"/*[Ee]quinox*.sh; do
      [ -f "$cand" ] || continue
      [ "$(basename "$cand")" = "$(basename "$SCRIPT_PATH")" ] && continue
      if validate_core "$cand"; then CORE_SRC="$cand"; ok "Inti ditemukan: $cand"; return 0; fi
    done
  fi

  if [ "$OFFLINE" -eq 1 ]; then
    die "Mode --offline: $CORE_NAME tidak ditemukan di $SCRIPT_DIR"
  fi
  info "Mengunduh inti terbaru dari GitHub..."
  if download_core; then return 0; fi
  die "Tidak menemukan $CORE_NAME di $SCRIPT_DIR dan gagal mengunduhnya. Pastikan file inti ada di folder repo yang sama dengan Installer.sh."
}

core_version() { sed -n 's/^EQX_VERSION="\(.*\)"/\1/p' "$1" 2>/dev/null | head -n 1; }

# -----------------------------------------------------------------------------
# 5-6. Pemasangan berkas, launcher, metadata
# -----------------------------------------------------------------------------
backup_existing() {
  if [ -f "$LIB_DIR/$CORE_NAME" ]; then
    local bdir="$DATA_DIR/backups/install-$STAMP"
    mkdir -p "$bdir" 2>/dev/null && cp -a "$LIB_DIR/." "$bdir/" 2>>"$LOGFILE" && ok "Instalasi lama dicadangkan: $bdir"
    PREV_VERSION="$(core_version "$LIB_DIR/$CORE_NAME")"
    [ -n "${PREV_VERSION:-}" ] && info "Versi sebelumnya: $PREV_VERSION"
  fi
}

install_files() {
  local newv
  newv="$(core_version "$CORE_SRC")"
  mkdir -p "$LIB_DIR" "$BIN_DIR" || die "Gagal membuat direktori pemasangan"

  # Salin inti (buang CRLF bila file pernah diedit di Windows)
  sed 's/\r$//' "$CORE_SRC" >"$LIB_DIR/$CORE_NAME.tmp" 2>>"$LOGFILE" || die "Gagal menyalin inti"
  mv -f "$LIB_DIR/$CORE_NAME.tmp" "$LIB_DIR/$CORE_NAME" || die "Gagal menempatkan inti"
  chmod 755 "$LIB_DIR/$CORE_NAME"
  ok "Inti terpasang: $LIB_DIR/$CORE_NAME (v${newv:-?})"

  # Salin installer sendiri (dipakai oleh `eqx update` / `eqx uninstall`)
  if [ "$SCRIPT_DIR" != "$LIB_DIR" ] && [ -f "$SCRIPT_PATH" ]; then
    sed 's/\r$//' "$SCRIPT_PATH" >"$LIB_DIR/installer.sh.tmp" 2>>"$LOGFILE" \
      && mv -f "$LIB_DIR/installer.sh.tmp" "$LIB_DIR/installer.sh" && chmod 755 "$LIB_DIR/installer.sh"
  fi

  # Dokumentasi (jika ada)
  local doc
  for doc in README.md Readme.md readme.md; do
    if [ -f "$SCRIPT_DIR/$doc" ]; then cp -f "$SCRIPT_DIR/$doc" "$LIB_DIR/README.md" 2>/dev/null; break; fi
  done

  printf '%s\n' "${newv:-unknown}" >"$LIB_DIR/VERSION"
}

create_launcher() {
  cat >"$LAUNCHER.tmp" <<EOF
#!$BASH_BIN
# Peluncur Equinox - dibuat otomatis oleh Installer.sh v$INSTALLER_VERSION ($STAMP)
EQX_LIB="$LIB_DIR"
CORE="\$EQX_LIB/$CORE_NAME"
if [ ! -f "\$CORE" ]; then
  echo "Equinox: file inti tidak ditemukan di \$CORE" >&2
  echo "Jalankan ulang Installer.sh dari folder repo (atau: git clone $REPO_URL)." >&2
  exit 1
fi
if [ "\$#" -eq 0 ]; then
  exec "$BASH_BIN" --rcfile "\$CORE" -i
fi
exec "$BASH_BIN" "\$CORE" "\$@"
EOF
  mv -f "$LAUNCHER.tmp" "$LAUNCHER" || die "Gagal membuat peluncur $LAUNCHER"
  chmod 755 "$LAUNCHER"
  ok "Perintah dibuat: $LAUNCHER"

  rm -f "$LAUNCHER_ALIAS" 2>/dev/null
  if ln -s "$LAUNCHER" "$LAUNCHER_ALIAS" 2>>"$LOGFILE"; then
    ok "Perintah singkat dibuat: eqx"
  else
    sed "s#^# #;1s#.*#\#!$BASH_BIN#" "$LAUNCHER" >"$LAUNCHER_ALIAS" 2>/dev/null && chmod 755 "$LAUNCHER_ALIAS" && ok "Perintah singkat dibuat: eqx (salinan)"
fi
}

write_meta() {
  local repo_dir=""
  if [ -d "$SCRIPT_DIR/.git" ]; then repo_dir="$SCRIPT_DIR"; fi
  {
    printf 'VERSION=%s\n' "$(core_version "$LIB_DIR/$CORE_NAME")"
    printf 'INSTALLER=%s\n' "$INSTALLER_VERSION"
    printf 'REPO_DIR=%s\n' "$repo_dir"
    printf 'PREFIX=%s\n' "$INSTALL_PREFIX"
    printf 'BIN=%s\n' "$BIN_DIR"
    printf 'LIB=%s\n' "$LIB_DIR"
    printf 'TERMUX=%s\n' "$IS_TERMUX"
    printf 'INSTALLED_AT=%s\n' "$(date '+%F %T')"
  } >"$DATA_DIR/install.meta" 2>/dev/null && ok "Metadata instalasi ditulis"
}

init_config() {
  mkdir -p "$DATA_DIR"/{logs,plugins,notes,backups,cache,trash,themes} 2>/dev/null
  if [ ! -f "$DATA_DIR/equinox.conf" ]; then
    EQX_YES=1 "$LAUNCHER" config reset >>"$LOGFILE" 2>&1 && ok "Konfigurasi awal dibuat" || warn "Konfigurasi awal akan dibuat saat Equinox pertama dijalankan"
  else
    ok "Konfigurasi lama dipertahankan"
  fi
}

# -----------------------------------------------------------------------------
# 7. Autostart & PATH
# -----------------------------------------------------------------------------
rc_file() {
  # Termux & kebanyakan Linux memakai ~/.bashrc
  printf '%s' "$HOME/.bashrc"
}

remove_block() { # file awal akhir
  local f="$1" a="$2" b="$3"
  [ -f "$f" ] || return 0
  grep -qF "$a" "$f" 2>/dev/null || return 0
  sed "/^$(printf '%s' "$a" | sed 's/[][\.*^$/]/\\&/g')\$/,/^$(printf '%s' "$b" | sed 's/[][\.*^$/]/\\&/g')\$/d" "$f" >"$f.eqx.tmp" \
    && cat "$f.eqx.tmp" >"$f"
  rm -f "$f.eqx.tmp"
}

backup_rc() {
  local f; f="$(rc_file)"
  if [ -f "$f" ] && [ -z "${RC_BACKED:-}" ]; then
    cp -a "$f" "$f.equinox-bak-$STAMP" 2>/dev/null && info "Backup $f -> $f.equinox-bak-$STAMP"
    RC_BACKED=1
  fi
}

enable_autostart() {
  local f; f="$(rc_file)"
  backup_rc
  remove_block "$f" "$MARK_AUTO_BEGIN" "$MARK_AUTO_END"
  touch "$f"
  {
    printf '\n%s\n' "$MARK_AUTO_BEGIN"
    cat <<'EOF'
# Buka Equinox otomatis pada shell interaktif.
# Lewati sekali : EQX_SKIP=1 bash        Matikan permanen: touch ~/.equinox/noautostart
if [ -n "${PS1:-}" ] && [ -z "${EQUINOX_ACTIVE:-}" ] && [ -z "${EQX_SKIP:-}" ] \
   && [ ! -f "$HOME/.equinox/noautostart" ] && command -v equinox >/dev/null 2>&1; then
  _eqx_t0=$SECONDS
  equinox
  # Jika Equinox langsung berhenti (< 3 detik, mis. error) tetap pakai shell biasa
  if [ $(( SECONDS - _eqx_t0 )) -ge 3 ]; then exit; fi
  unset _eqx_t0
fi
EOF
    printf '%s\n' "$MARK_AUTO_END"
  } >>"$f"
  ok "Autostart diaktifkan di $f"
  dim "Matikan: touch ~/.equinox/noautostart   |   atau jalankan: ./Installer.sh --uninstall"
}

maybe_autostart() {
  case "$AUTOSTART" in
    yes) enable_autostart ;;
    no)  info "Autostart tidak diaktifkan" ;;
    ask)
      if [ "$MODE" = "update" ] || [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
        info "Autostart tidak diubah (aktifkan dengan --autostart)"
      elif ask_yn "Buka Equinox otomatis setiap Termux/shell dibuka?" n; then
        enable_autostart
      else
        info "Lewati autostart. Jalankan kapan saja dengan perintah: equinox"
      fi ;;
  esac
}

ensure_path() {
  case ":$PATH:" in *":$BIN_DIR:"*) return 0 ;; esac
  warn "$BIN_DIR belum ada di PATH"
  local f; f="$(rc_file)"
  backup_rc
  remove_block "$f" "$MARK_PATH_BEGIN" "$MARK_PATH_END"
  {
    printf '\n%s\n' "$MARK_PATH_BEGIN"
    printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$BIN_DIR" "$BIN_DIR"
    printf '%s\n' "$MARK_PATH_END"
  } >>"$f"
  export PATH="$BIN_DIR:$PATH"
  ok "PATH diperbarui di $f (berlaku untuk sesi baru)"
}

# -----------------------------------------------------------------------------
# 8. Verifikasi
# -----------------------------------------------------------------------------
verify_install() {
  local out
  [ -x "$LAUNCHER" ] || die "Peluncur tidak dapat dieksekusi: $LAUNCHER"
  [ -f "$LIB_DIR/$CORE_NAME" ] || die "Inti tidak ada di $LIB_DIR"
  bash -n "$LIB_DIR/$CORE_NAME" 2>>"$LOGFILE" || die "Inti terpasang memiliki galat sintaks"
  ok "Sintaks inti valid"

  out="$("$LAUNCHER" version 2>&1)" || { log "$out"; die "Peluncur gagal dijalankan: $out"; }
  case "$out" in *Equinox*) ok "Peluncur berfungsi" ;; *) die "Keluaran peluncur tidak sesuai: $out" ;; esac

  if "$BASH_BIN" "$LIB_DIR/$CORE_NAME" selftest --quiet >>"$LOGFILE" 2>&1; then
    ok "Uji mandiri lulus"
  else
    warn "Uji mandiri melaporkan masalah. Jalankan: equinox selftest   (log: $LOGFILE)"
  fi
}

print_summary() {
  local ver; ver="$(core_version "$LIB_DIR/$CORE_NAME")"
  printf '\n  %s✔ %s v%s berhasil dipasang!%s\n' "$C_OK$C_B" "$APP_NAME" "${ver:-?}" "$C_R"
  printf '  %s────────────────────────────────────────%s\n\n' "$C_OK" "$C_R"
  printf '  %sMulai sekarang:%s\n' "$C_B" "$C_R"
  printf '    %sequinox%s            shell interaktif Equinox\n' "$C_P" "$C_R"
  printf '    %seqx help%s           daftar semua perintah\n' "$C_P" "$C_R"
  printf '    %seqx menu%s           menu interaktif\n' "$C_P" "$C_R"
  printf '    %seqx doctor%s         cek dependensi\n' "$C_P" "$C_R"
  printf '    %seqx update%s         perbarui dari GitHub\n' "$C_P" "$C_R"
  printf '\n  %sLog instalasi:%s %s\n' "$C_D" "$C_R" "$LOGFILE"
  if [ "$IS_TERMUX" -eq 1 ]; then
    printf '  %sTips Termux:%s eqx termux storage  (akses penyimpanan)  |  eqx termux keys  (extra keys)\n' "$C_D" "$C_R"
  fi
  printf '\n'
}

# -----------------------------------------------------------------------------
# Mode: check
# -----------------------------------------------------------------------------
do_check() {
  local c bad=0
  printf '\n%sPeriksa kesiapan sistem%s\n\n' "$C_B" "$C_R"
  info "OS: $OS_NAME ($ARCH)  |  Termux: $( [ "$IS_TERMUX" -eq 1 ] && echo ya || echo tidak )"
  info "Bash: $BASH_VERSION  |  Pkg manager: $PKGMGR  |  Prefix: $INSTALL_PREFIX"
  for c in "${REQUIRED_CMDS[@]}"; do
    if have "$c"; then printf '  %s✔%s %s\n' "$C_OK" "$C_R" "$c"
    else printf '  %s✘%s %s  (paket: %s)\n' "$C_E" "$C_R" "$c" "$(pkg_for "$c")"; bad=$(( bad + 1 )); fi
  done
  if [ -f "$LIB_DIR/$CORE_NAME" ]; then info "Equinox terpasang: v$(core_version "$LIB_DIR/$CORE_NAME") di $LIB_DIR"
  else info "Equinox belum terpasang"; fi
  find_core_quiet
  if [ "$bad" -eq 0 ]; then ok "Sistem siap. Jalankan ./Installer.sh untuk memasang."; return 0; fi
  err "$bad perintah wajib hilang. Installer dapat memasangnya otomatis."
  return 1
}

find_core_quiet() {
  local cand
  for cand in "$SCRIPT_DIR/$CORE_NAME" "$SCRIPT_DIR"/*[Cc]ore*.sh; do
    [ -f "$cand" ] || continue
    if validate_core "$cand"; then ok "File inti lokal valid: $cand"; return 0; fi
  done
  warn "File inti lokal tidak ditemukan di $SCRIPT_DIR (akan diunduh dari GitHub)"
}

# -----------------------------------------------------------------------------
# Mode: uninstall
# -----------------------------------------------------------------------------
do_uninstall() {
  local meta="$DATA_DIR/install.meta" v
  if [ -f "$meta" ]; then
    v="$(sed -n 's/^BIN=//p' "$meta" | head -n 1)";  [ -n "$v" ] && BIN_DIR="$v"
    v="$(sed -n 's/^LIB=//p' "$meta" | head -n 1)";  [ -n "$v" ] && LIB_DIR="$v"
    LAUNCHER="$BIN_DIR/equinox"; LAUNCHER_ALIAS="$BIN_DIR/eqx"
  fi
  printf '\n%sMencopot Equinox%s\n\n' "$C_B" "$C_R"
  info "Peluncur : $LAUNCHER"
  info "Pustaka  : $LIB_DIR"
  if ! ask_yn "Lanjutkan mencopot Equinox?" n honor-yes; then info "Dibatalkan"; return 0; fi

  rm -f "$LAUNCHER" && ok "Dihapus: $LAUNCHER"
  if [ -L "$LAUNCHER_ALIAS" ] || [ -f "$LAUNCHER_ALIAS" ]; then rm -f "$LAUNCHER_ALIAS" && ok "Dihapus: $LAUNCHER_ALIAS"; fi
  # Hapus pustaka (hati-hati: hanya jika benar-benar folder equinox)
  if [ -d "$LIB_DIR" ] && [ "$(basename "$LIB_DIR")" = "equinox" ]; then
    rm -rf "$LIB_DIR" && ok "Dihapus: $LIB_DIR"
  fi
  local f; f="$(rc_file)"
  if [ -f "$f" ] && { grep -qF "$MARK_AUTO_BEGIN" "$f" || grep -qF "$MARK_PATH_BEGIN" "$f"; }; then
    backup_rc
    remove_block "$f" "$MARK_AUTO_BEGIN" "$MARK_AUTO_END"
    remove_block "$f" "$MARK_PATH_BEGIN" "$MARK_PATH_END"
    ok "Blok autostart/PATH dibersihkan dari $f"
  fi
  if [ -d "$DATA_DIR" ]; then
    if [ "$PURGE" -eq 1 ] || ask_yn "Hapus juga data pribadi (catatan, todo, backup, config) di $DATA_DIR?" n; then
      rm -rf "$DATA_DIR" && ok "Data dihapus: $DATA_DIR"
    else
      info "Data dipertahankan di $DATA_DIR"
    fi
  fi
  printf '\n  %sEquinox telah dicopot.%s Sampai jumpa!\n\n' "$C_OK" "$C_R"
}

# -----------------------------------------------------------------------------
# Mode: install / update
# -----------------------------------------------------------------------------
do_install() {
  if [ "$MODE" = "update" ]; then TOTAL_STEPS=6; fi

  step "Mendeteksi lingkungan & pemeriksaan awal"
  preflight

  step "Dependensi"
  install_deps

  step "Mencari berkas inti Equinox"
  find_core

  step "Memasang berkas"
  backup_existing
  install_files

  step "Membuat perintah equinox / eqx"
  create_launcher
  write_meta
  ensure_path
  if [ "$MODE" != "update" ]; then init_config; fi

  if [ "$MODE" != "update" ]; then
    step "Pengaturan opsional"
    maybe_autostart
  elif [ "$AUTOSTART" = "yes" ]; then
    enable_autostart
  fi

  step "Verifikasi"
  verify_install

  print_summary
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  parse_args "$@"
  banner
  detect_env
  case "$MODE" in
    check)     do_check; exit $? ;;
    uninstall) do_uninstall; exit 0 ;;
    install|update) do_install ;;
  esac
}

main "$@"
