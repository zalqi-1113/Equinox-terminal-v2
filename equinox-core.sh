#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC1090,SC1091,SC2155,SC2086,SC2120,SC2119,SC2016
# =============================================================================
#  EQUINOX CORE  -  inti Linux Terminal Equinox untuk Termux (juga jalan di Linux)
#
#  Versi  : 1.0.0 "Solstice"
#  Repo   : https://github.com/zalqi-1113/Equinox-Linux-Terminal-
#
#  Dua mode pemakaian:
#    1) Di-source lewat `bash --rcfile equinox-core.sh -i`  -> shell interaktif
#    2) Dijalankan dengan argumen: `equinox <perintah> ...`  -> mode CLI
#
#  Struktur file ini:
#    1. Lingkungan, warna & tema, helper UI, konfigurasi
#    2. Prompt, alias, fungsi shell, informasi sistem, monitor
#    3. Jaringan, berkas, produktivitas
#    4. Keamanan, paket, Termux, kustomisasi, hiburan, pemeliharaan, menu
#    5. Registrasi perintah, dispatcher, titik masuk
# =============================================================================

# Hindari pemuatan ganda saat di-source
if [[ -n "${EQX_CORE_LOADED:-}" && "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

# Butuh Bash >= 4.2 (array asosiatif, declare -g, dll.)
if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2 ) )); then
  printf 'Equinox membutuhkan Bash 4.2 atau lebih baru (terdeteksi: %s)\n' "$BASH_VERSION" >&2
  return 1 2>/dev/null || exit 1
fi
EQX_CORE_LOADED=1

# -----------------------------------------------------------------------------
# 1. METADATA & PATH
# -----------------------------------------------------------------------------
EQX_NAME="Equinox"
EQX_VERSION="1.0.0"
EQX_CODENAME="Solstice"
EQX_AUTHOR="zalqi-1113"
EQX_REPO_URL="https://github.com/zalqi-1113/Equinox-Linux-Terminal-"
EQX_RAW_URL="https://raw.githubusercontent.com/zalqi-1113/Equinox-Linux-Terminal-"

EQX_SELF="${BASH_SOURCE[0]}"
EQX_LIB="$(cd "$(dirname "$EQX_SELF")" 2>/dev/null && pwd)"
EQX_HOME="${EQX_HOME:-$HOME/.equinox}"
EQX_CONF="$EQX_HOME/equinox.conf"
EQX_META="$EQX_HOME/install.meta"
EQX_LOGFILE="$EQX_HOME/logs/equinox.log"
EQX_NOTES_FILE="$EQX_HOME/notes/notes.tsv"
EQX_TODO_FILE="$EQX_HOME/notes/todo.tsv"
EQX_BM_FILE="$EQX_HOME/bookmarks.tsv"
EQX_ALIAS_FILE="$EQX_HOME/aliases.sh"
EQX_HISTFILE="$EQX_HOME/history"
EQX_TRASH_DIR="$EQX_HOME/trash"
EQX_PLUGIN_DIR="$EQX_HOME/plugins"
EQX_BACKUP_DIR="$EQX_HOME/backups"
EQX_STOP=0

# -----------------------------------------------------------------------------
# 2. DETEKSI LINGKUNGAN
# -----------------------------------------------------------------------------
eqx_have() { command -v "$1" >/dev/null 2>&1; }

eqx_detect_env() {
  EQX_IS_TERMUX=0
  if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *com.termux* || -d /data/data/com.termux/files/usr ]]; then
    EQX_IS_TERMUX=1
  fi
  EQX_ARCH="$(uname -m 2>/dev/null || echo unknown)"
  EQX_KERNEL="$(uname -sr 2>/dev/null || echo unknown)"
  EQX_PKGMGR="none"
  if (( EQX_IS_TERMUX )) && eqx_have pkg; then EQX_PKGMGR="pkg"
  elif eqx_have apt-get; then EQX_PKGMGR="apt"
  elif eqx_have dnf; then EQX_PKGMGR="dnf"
  elif eqx_have pacman; then EQX_PKGMGR="pacman"
  elif eqx_have apk; then EQX_PKGMGR="apk"
  elif eqx_have zypper; then EQX_PKGMGR="zypper"
  fi
  EQX_SUDO=""
  if (( EUID != 0 )) && (( ! EQX_IS_TERMUX )) && eqx_have sudo; then EQX_SUDO="sudo"; fi
  if (( EQX_IS_TERMUX )) && [[ -z "${LANG:-}" ]]; then export LANG="en_US.UTF-8"; fi
}

eqx_tmpdir() {
  local d="${TMPDIR:-}"
  [[ -z "$d" && -n "${PREFIX:-}" && -d "${PREFIX}/tmp" ]] && d="${PREFIX}/tmp"
  [[ -z "$d" && -d /tmp && -w /tmp ]] && d="/tmp"
  [[ -z "$d" ]] && d="$EQX_HOME/cache"
  mkdir -p "$d" 2>/dev/null
  printf '%s' "$d"
}

eqx_tmpfile() {
  local d f
  d="$(eqx_tmpdir)"
  f="$(mktemp "$d/eqx.XXXXXX" 2>/dev/null)" || f="$d/eqx.$$.$RANDOM"
  : >"$f" 2>/dev/null
  printf '%s' "$f"
}

eqx_ensure_dirs() {
  local d
  for d in "$EQX_HOME" "$EQX_HOME"/{logs,plugins,notes,backups,cache,trash,themes}; do
    [[ -d "$d" ]] || mkdir -p "$d" 2>/dev/null
  done
  [[ -w "$EQX_HOME" ]]
}

eqx_log() { # level pesan...
  local lvl="${1:-INFO}"; shift
  [[ -w "$EQX_HOME/logs" ]] || return 0
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$lvl" "$*" >>"$EQX_LOGFILE" 2>/dev/null
  local sz
  sz=$(wc -c <"$EQX_LOGFILE" 2>/dev/null || echo 0)
  if (( sz > 524288 )); then
    tail -n 500 "$EQX_LOGFILE" >"$EQX_LOGFILE.tmp" 2>/dev/null && mv -f "$EQX_LOGFILE.tmp" "$EQX_LOGFILE"
  fi
  return 0
}

# -----------------------------------------------------------------------------
# 3. KONFIGURASI
# -----------------------------------------------------------------------------
declare -gA EQX_CFG=()
declare -gA EQX_CFG_DEF=(
  [THEME]="equinox"
  [PROMPT_STYLE]="equinox"
  [PROMPT_USER]=""
  [UNICODE]="auto"
  [BANNER]="on"
  [TIPS]="on"
  [GIT_PROMPT]="on"
  [GIT_DIRTY]="off"
  [HIST_SIZE]="5000"
  [LOAD_BASHRC]="off"
  [WEATHER_CITY]=""
  [EDITOR_CMD]=""
  [CONFIRM_DANGEROUS]="on"
  [UPDATE_BRANCH]="main"
)
EQX_CFG_ORDER=(THEME PROMPT_STYLE PROMPT_USER UNICODE BANNER TIPS GIT_PROMPT GIT_DIRTY HIST_SIZE LOAD_BASHRC WEATHER_CITY EDITOR_CMD CONFIRM_DANGEROUS UPDATE_BRANCH)
EQX_PROMPT_STYLES=(equinox minimal classic hacker lean arrow)

declare -gA EQX_THEMES=(
  [equinox]="39 141 78 221 203 244 252"
  [aurora]="49 213 84 227 197 243 255"
  [ocean]="33 45 42 220 160 245 153"
  [sunset]="208 205 112 226 196 244 223"
  [matrix]="46 34 46 190 160 22 120"
  [dracula]="141 212 84 228 203 61 253"
  [nord]="110 139 108 179 167 60 188"
  [mono]="250 255 250 250 250 240 252"
)
EQX_THEME_ORDER=(equinox aurora ocean sunset matrix dracula nord mono)

eqx_cfg_load() {
  local k line key val re_dq='^"(.*)"$' re_sq="^'(.*)'\$"
  EQX_CFG=()
  for k in "${!EQX_CFG_DEF[@]}"; do EQX_CFG[$k]="${EQX_CFG_DEF[$k]}"; done
  [[ -f "$EQX_CONF" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      if [[ "$val" =~ $re_dq ]]; then val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ $re_sq ]]; then val="${BASH_REMATCH[1]}"; fi
      [[ -n "${EQX_CFG_DEF[$key]+x}" ]] && EQX_CFG[$key]="$val"
    fi
  done <"$EQX_CONF"
  return 0
}

eqx_cfg_save() {
  local k tmp="$EQX_CONF.tmp.$$"
  mkdir -p "$EQX_HOME" 2>/dev/null || return 1
  {
    printf '# Konfigurasi Equinox %s\n' "$EQX_VERSION"
    printf '# Ubah lewat: eqx config set KUNCI NILAI   (atau edit manual)\n'
    for k in "${EQX_CFG_ORDER[@]}"; do
      printf '%s="%s"\n' "$k" "${EQX_CFG[$k]}"
    done
  } >"$tmp" 2>/dev/null && mv -f "$tmp" "$EQX_CONF"
}

eqx_cfg_validate() { # kunci nilai -> 0 valid; 1 tidak valid (pesan di stdout)
  local k="$1" v="$2"
  if [[ "$v" == *$'\n'* || "$v" == *'"'* || "$v" == *'\'* ]]; then
    echo "nilai tidak boleh mengandung tanda kutip ganda, backslash, atau baris baru"; return 1
  fi
  case "$k" in
    THEME)
      [[ -n "${EQX_THEMES[$v]:-}" ]] || { echo "tema tidak dikenal. pilihan: ${EQX_THEME_ORDER[*]}"; return 1; } ;;
    PROMPT_STYLE)
      [[ " ${EQX_PROMPT_STYLES[*]} " == *" $v "* ]] || { echo "gaya tidak dikenal. pilihan: ${EQX_PROMPT_STYLES[*]}"; return 1; } ;;
    UNICODE)
      [[ "$v" =~ ^(auto|on|off)$ ]] || { echo "isi dengan: auto | on | off"; return 1; } ;;
    BANNER|TIPS|GIT_PROMPT|GIT_DIRTY|LOAD_BASHRC|CONFIRM_DANGEROUS)
      [[ "$v" =~ ^(on|off)$ ]] || { echo "isi dengan: on | off"; return 1; } ;;
    HIST_SIZE)
      [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 100 && v <= 1000000 )) || { echo "isi dengan angka 100 - 1000000"; return 1; } ;;
    UPDATE_BRANCH)
      [[ "$v" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "nama branch tidak valid"; return 1; } ;;
    PROMPT_USER)
      [[ "$v" =~ ^[A-Za-z0-9._-]{0,24}$ ]] || { echo "maks 24 karakter: huruf, angka, titik, minus, underscore"; return 1; } ;;
    WEATHER_CITY)
      [[ "$v" =~ ^[A-Za-z0-9\ ,._+-]{0,40}$ ]] || { echo "nama kota tidak valid"; return 1; } ;;
    EDITOR_CMD)
      [[ -z "$v" ]] || eqx_have "${v%% *}" || { echo "editor '${v%% *}' tidak ditemukan"; return 1; } ;;
  esac
  return 0
}

eqx_cfg_get() { printf '%s' "${EQX_CFG[$1]-}"; }

eqx_cfg_set() { # kunci nilai
  local k="${1^^}" v="$2" msg
  [[ -n "${EQX_CFG_DEF[$k]+x}" ]] || { eqx_err "kunci tidak dikenal: $k (lihat: eqx config list)"; return 1; }
  if ! msg="$(eqx_cfg_validate "$k" "$v")"; then eqx_err "$k: $msg"; return 1; fi
  EQX_CFG[$k]="$v"
  eqx_cfg_save || { eqx_err "gagal menyimpan konfigurasi ke $EQX_CONF"; return 1; }
  eqx_log INFO "config $k=$v"
  return 0
}

# -----------------------------------------------------------------------------
# 4. WARNA, SIMBOL, TEMA
# -----------------------------------------------------------------------------
eqx_colors_init() {
  if [[ -n "${NO_COLOR:-}" || "${TERM:-dumb}" == "dumb" ]]; then
    EQX_COLOR=0
  elif [[ -t 1 || -n "${EQX_FORCE_COLOR:-}" ]]; then
    EQX_COLOR=1
  else
    EQX_COLOR=0
  fi
}

eqx_symbols_init() {
  local uni="${EQX_CFG[UNICODE]:-auto}"
  if [[ "$uni" == auto ]]; then
    if (( EQX_IS_TERMUX )) || [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then uni=on; else uni=off; fi
  fi
  if [[ "$uni" == on ]]; then
    EQX_UNI=1
    S_OK='✔'; S_ERR='✘'; S_WARN='▲'; S_INFO='●'; S_ARR='➜'; S_DOT='•'; S_GIT='⎇ '
    S_FULL='█'; S_EMPTY='░'; S_PROMPT='❯'
    B_TL='╭'; B_TR='╮'; B_BL='╰'; B_BR='╯'; B_H='─'; B_V='│'; B_DL='┌'; B_DB='└'; B_T='├'
    EQX_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  else
    EQX_UNI=0
    S_OK='+'; S_ERR='x'; S_WARN='!'; S_INFO='*'; S_ARR='->'; S_DOT='*'; S_GIT='git:'
    S_FULL='#'; S_EMPTY='-'; S_PROMPT='>'
    B_TL='+'; B_TR='+'; B_BL='+'; B_BR='+'; B_H='-'; B_V='|'; B_DL=','; B_DB="'"; B_T='+'
    EQX_SPIN=('|' '/' '-' '\')
  fi
}

eqx_colors_rebuild() {
  if (( EQX_COLOR )); then
    C_R=$'\e[0m'; C_B=$'\e[1m'; C_DIM=$'\e[2m'; C_I=$'\e[3m'; C_U=$'\e[4m'
    printf -v C_P  '\e[38;5;%sm' "$TH_P"
    printf -v C_A  '\e[38;5;%sm' "$TH_A"
    printf -v C_OK '\e[38;5;%sm' "$TH_OK"
    printf -v C_W  '\e[38;5;%sm' "$TH_W"
    printf -v C_E  '\e[38;5;%sm' "$TH_E"
    printf -v C_D  '\e[38;5;%sm' "$TH_D"
    printf -v C_T  '\e[38;5;%sm' "$TH_T"
  else
    C_R=""; C_B=""; C_DIM=""; C_I=""; C_U=""; C_P=""; C_A=""; C_OK=""; C_W=""; C_E=""; C_D=""; C_T=""
  fi
}

eqx_theme_apply() {
  local name="${1:-equinox}"
  [[ -n "${EQX_THEMES[$name]:-}" ]] || name="equinox"
  read -r TH_P TH_A TH_OK TH_W TH_E TH_D TH_T <<<"${EQX_THEMES[$name]}"
  EQX_THEME_NAME="$name"
  eqx_colors_rebuild
}

# -----------------------------------------------------------------------------
# 5. HELPER UI
# -----------------------------------------------------------------------------
eqx_info() { printf '%s%s%s %s\n' "$C_P" "$S_INFO" "$C_R" "$*"; }
eqx_ok()   { printf '%s%s%s %s\n' "$C_OK" "$S_OK" "$C_R" "$*"; }
eqx_warn() { printf '%s%s%s %s\n' "$C_W" "$S_WARN" "$C_R" "$*" >&2; }
eqx_err()  { printf '%s%s%s %s\n' "$C_E" "$S_ERR" "$C_R" "$*" >&2; }
eqx_dim()  { printf '%s%s%s\n' "$C_D" "$*" "$C_R"; }
eqx_step() { printf '%s%s%s %s%s%s\n' "$C_A" "$S_ARR" "$C_R" "$C_B" "$*" "$C_R"; }

eqx_cols() {
  local c
  c="$(tput cols 2>/dev/null)" || c=""
  [[ "$c" =~ ^[0-9]+$ ]] && (( c > 0 )) || c="${COLUMNS:-80}"
  printf '%s' "$c"
}

eqx_rows() {
  local r
  r="$(tput lines 2>/dev/null)" || r=""
  [[ "$r" =~ ^[0-9]+$ ]] && (( r > 0 )) || r="${LINES:-24}"
  printf '%s' "$r"
}

eqx_hr() { # [karakter] [lebar]
  local ch="${1:-$B_H}" n="${2:-$(eqx_cols)}" line
  (( n > 100 )) && n=100
  printf -v line '%*s' "$n" ''
  printf '%s%s%s\n' "$C_D" "${line// /$ch}" "$C_R"
}

eqx_title() {
  local t=" $* " line w
  w=${#t}
  printf -v line '%*s' "$w" ''
  printf '%s%s%s%s\n' "$C_P" "$B_TL" "${line// /$B_H}" "$B_TR$C_R"
  printf '%s%s%s%s%s%s\n' "$C_P" "$B_V" "$C_R$C_B" "$t" "$C_R$C_P$B_V" "$C_R"
  printf '%s%s%s%s\n' "$C_P" "$B_BL" "${line// /$B_H}" "$B_BR$C_R"
}

eqx_section() { printf '\n%s%s %s%s\n' "$C_A" "$S_ARR" "$*" "$C_R"; }

eqx_kv() { # label nilai [lebar-label]
  printf '  %s%-*s%s %s\n' "$C_A" "${3:-11}" "$1" "$C_R" "$2"
}

eqx_need() { # perintah [paket]
  if ! eqx_have "$1"; then
    eqx_err "perintah '$1' tidak ditemukan. Pasang dulu: eqx pkg install ${2:-$1}"
    return 1
  fi
}

eqx_human() { # byte -> teks mudah dibaca
  awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}
    if(i==1)printf "%d %s",b,u[i]; else printf "%.1f %s",b,u[i]}'
}

eqx_human_kb() { eqx_human "$(( ${1:-0} * 1024 ))"; }

eqx_dur() { # detik -> "1d 2h 3m 4s"
  local s="${1:-0}" d h m out=""
  d=$(( s / 86400 )); h=$(( s % 86400 / 3600 )); m=$(( s % 3600 / 60 )); s=$(( s % 60 ))
  (( d > 0 )) && out+="${d}d "
  (( d > 0 || h > 0 )) && out+="${h}h "
  (( d > 0 || h > 0 || m > 0 )) && out+="${m}m "
  [[ -z "$out" ]] && out="${s}s" || out="${out% }"
  printf '%s' "$out"
}

eqx_hms() { # detik -> HH:MM:SS
  local s="${1:-0}"
  printf '%02d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
}

eqx_parse_duration() { # "1h30m15s" | "90" | "5m" -> detik
  local s="${1,,}"
  [[ -n "$s" ]] || return 1
  if [[ "$s" =~ ^[0-9]+$ ]]; then printf '%s' "$((10#$s))"; return 0; fi
  local re='^(([0-9]+)d)?(([0-9]+)h)?(([0-9]+)m)?(([0-9]+)s)?$'
  if [[ "$s" =~ $re ]]; then
    local d="${BASH_REMATCH[2]:-0}" h="${BASH_REMATCH[4]:-0}" m="${BASH_REMATCH[6]:-0}" x="${BASH_REMATCH[8]:-0}"
    printf '%s' "$(( 10#$d * 86400 + 10#$h * 3600 + 10#$m * 60 + 10#$x ))"
    return 0
  fi
  return 1
}

eqx_bar() { # persen [lebar]
  local pct="${1:-0}" w="${2:-20}" f e col fs es
  pct="${pct%.*}"; [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
  (( pct > 100 )) && pct=100
  f=$(( pct * w / 100 )); e=$(( w - f ))
  if (( pct >= 85 )); then col="$C_E"; elif (( pct >= 60 )); then col="$C_W"; else col="$C_OK"; fi
  printf -v fs '%*s' "$f" ''; printf -v es '%*s' "$e" ''
  printf '%s%s%s%s %3d%%' "$col" "${fs// /$S_FULL}" "$C_D" "${es// /$S_EMPTY}$C_R" "$pct"
}

eqx_confirm() { # pertanyaan [default y|n]
  local q="$1" def="${2:-n}" ans hint
  [[ "$def" == y ]] && hint="Y/n" || hint="y/N"
  [[ -n "${EQX_YES:-}" ]] && return 0
  if [[ ! -t 0 ]]; then [[ "$def" == y ]]; return; fi
  read -r -p "$(printf '%s?%s %s [%s] ' "$C_W" "$C_R" "$q" "$hint")" ans
  ans="${ans:-$def}"
  [[ "${ans,,}" =~ ^(y|ya|yes)$ ]]
}

eqx_ask() { # pertanyaan namavar [default]
  local __p="$1" __v="$2" __d="${3:-}" __a=""
  read -r -p "$(printf '%s?%s %s%s ' "$C_A" "$C_R" "$__p" "${__d:+ [$__d]}")" __a
  printf -v "$__v" '%s' "${__a:-$__d}"
}

eqx_run() { # pesan perintah...  (jalankan dengan spinner)
  local msg="$1"; shift
  local out pid rc i=0 had_m=0
  out="$(eqx_tmpfile)"
  [[ $- == *m* ]] && { had_m=1; set +m; }
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  if [[ -t 1 ]]; then
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s%s%s %s' "$C_P" "${EQX_SPIN[i % ${#EQX_SPIN[@]}]}" "$C_R" "$msg"
      i=$(( i + 1 )); sleep 0.1
    done
    tput cnorm 2>/dev/null
    printf '\r\033[K'
  fi
  wait "$pid"; rc=$?
  (( had_m )) && set -m
  if (( rc == 0 )); then
    eqx_ok "$msg"
  else
    eqx_err "$msg (kode keluar $rc)"
    tail -n 8 "$out" | sed 's/^/    /' >&2
  fi
  rm -f "$out"
  return $rc
}

eqx_screen_enter() {
  EQX_STOP=0
  tput smcup 2>/dev/null; tput civis 2>/dev/null
  printf '\033[2J\033[H'
  trap 'EQX_STOP=1' INT
}

eqx_screen_leave() {
  tput cnorm 2>/dev/null; tput rmcup 2>/dev/null
  trap - INT
  EQX_STOP=0
}

eqx_line() { printf '%s\033[K\n' "$*"; }  # satu baris frame (hapus sisa baris)

eqx_alert() { # pesan
  local msg="${1:-Selesai}"
  printf '\a'
  eqx_ok "$msg"
  eqx_have termux-notification && timeout 5 termux-notification --title "Equinox" --content "$msg" >/dev/null 2>&1
  eqx_have termux-vibrate && timeout 5 termux-vibrate -d 300 >/dev/null 2>&1
  return 0
}

eqx_editor() {
  local e="${EQX_CFG[EDITOR_CMD]:-}"
  [[ -z "$e" ]] && e="${EDITOR:-}"
  if [[ -z "$e" ]]; then
    for e in nano vim vi; do eqx_have "$e" && break; e=""; done
  fi
  printf '%s' "$e"
}

eqx_logo() {
  printf '%s' "$C_P"
  cat <<'EOF'
 ___    ___    _   _   ___   _  _    ___   __  __
| __|  / _ \  | | | | |_ _| | \| |  / _ \  \ \/ /
| _|  | (_) | | |_| |  | |  | .` | | (_) |  >  < 
|___|  \__\_\  \___/  |___| |_|\_|  \___/  /_/\_\
EOF
  printf '%s' "$C_R"
}

eqx_logo_small() {
  printf '%s%s EQUINOX %s%s  v%s "%s"%s\n' "$C_B" "$C_P" "$C_R" "$C_D" "$EQX_VERSION" "$EQX_CODENAME" "$C_R"
}

# Font digit besar (5 baris) untuk jam, timer, dan stopwatch
declare -gA EQX_DIGITS=(
  [0]="XXX|X X|X X|X X|XXX"
  [1]="  X|  X|  X|  X|  X"
  [2]="XXX|  X|XXX|X  |XXX"
  [3]="XXX|  X|XXX|  X|XXX"
  [4]="X X|X X|XXX|  X|  X"
  [5]="XXX|X  |XXX|  X|XXX"
  [6]="XXX|X  |XXX|X X|XXX"
  [7]="XXX|  X|  X|  X|  X"
  [8]="XXX|X X|XXX|X X|XXX"
  [9]="XXX|X X|XXX|  X|XXX"
  [:]="   | X |   | X |   "
  [.]="   |   |   |   | X "
)

eqx_bigtext() { # teks berisi digit, ':' dan '.'
  local txt="$1" r ch i l
  local -a rows=() out=("" "" "" "" "")
  for (( i = 0; i < ${#txt}; i++ )); do
    ch="${txt:i:1}"
    IFS='|' read -r -a rows <<<"${EQX_DIGITS[$ch]:-   |   |   |   |   }"
    for r in 0 1 2 3 4; do out[r]+="${rows[r]}  "; done
  done
  for r in 0 1 2 3 4; do
    l="${out[r]//X/$S_FULL}"
    printf '  %s%s%s\033[K\n' "$C_P" "$l" "$C_R"
  done
}

# -----------------------------------------------------------------------------
# 6. BOOTSTRAP
# -----------------------------------------------------------------------------
eqx_bootstrap() {
  eqx_detect_env
  eqx_ensure_dirs
  eqx_cfg_load
  eqx_colors_init
  eqx_symbols_init
  eqx_theme_apply "${EQX_CFG[THEME]}"
}

# =============================================================================
# 7. PROMPT
# =============================================================================
eqx_git_segment() {
  EQX_GIT_SEG=""
  [[ "${EQX_CFG[GIT_PROMPT]}" == on ]] || return 0
  eqx_have git || return 0
  local b mark=""
  b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)" || return 0
  [[ -n "$b" ]] || return 0
  if [[ "${EQX_CFG[GIT_DIRTY]}" == on ]]; then
    [[ -n "$(git status --porcelain 2>/dev/null | head -n 1)" ]] && mark="*"
  fi
  EQX_GIT_SEG=" ${S_GIT}${b}${mark}"
}

eqx_user_display() {
  local u="${EQX_CFG[PROMPT_USER]:-}"
  if [[ -z "$u" ]]; then
    if (( EQX_IS_TERMUX )); then u="equinox"; else u="$(id -un 2>/dev/null || echo "${USER:-user}")"; fi
  fi
  EQX_USERDISP="$u"
}

# Catatan keamanan: nilai dinamis (cabang git, kode keluar, nama user) TIDAK
# ditanam ke string PS1, hanya direferensikan lewat variabel, supaya tidak
# pernah dievaluasi sebagai perintah.
eqx_build_prompt() { # kode_keluar
  local ec="${1:-0}" style="${EQX_CFG[PROMPT_STYLE]}"
  local P="\[\e[38;5;${TH_P}m\]" A="\[\e[38;5;${TH_A}m\]" O="\[\e[38;5;${TH_OK}m\]"
  local W="\[\e[38;5;${TH_W}m\]" E="\[\e[38;5;${TH_E}m\]" D="\[\e[38;5;${TH_D}m\]"
  local R="\[\e[0m\]" B="\[\e[1m\]"
  local arrow="$S_PROMPT" ac="$O"
  eqx_git_segment
  eqx_user_display
  EQX_EC_SEG=""
  if (( ec != 0 )); then EQX_EC_SEG=" ${S_ERR}${ec}"; ac="$E"; fi
  case "$style" in
    minimal)
      PS1="${A}\W${R}${P}\${EQX_GIT_SEG}${R} ${ac}${arrow}${R} " ;;
    classic)
      PS1="${O}\u@\h${R}:${P}\w${R}\\\$ " ;;
    hacker)
      PS1="${P}${B_DL}${B_H}${B_H}(${R}${A}\${EQX_USERDISP}${R}${P}@${R}${A}\h${R}${P})-[${R}${B}\w${R}${P}]${R}${W}\${EQX_GIT_SEG}${R}${E}\${EQX_EC_SEG}${R}\n${P}${B_DB}${B_H}${R}${ac}\\\$${R} " ;;
    lean)
      PS1="${D}\A${R} ${A}\${EQX_USERDISP}${R} ${P}\W${R}${W}\${EQX_GIT_SEG}${R}${E}\${EQX_EC_SEG}${R} ${ac}${arrow}${R} " ;;
    arrow)
      PS1="${P}\w${R}${W}\${EQX_GIT_SEG}${R} ${ac}${S_ARR}${R} " ;;
    *)
      PS1="${P}${B_TL}${B_H} ${R}${A}\${EQX_USERDISP}${R}${D} in ${R}${P}\w${R}${W}\${EQX_GIT_SEG}${R}${E}\${EQX_EC_SEG}${R}${D} \A${R}\n${P}${B_BL}${B_H}${R}${ac}${arrow}${R} " ;;
  esac
  PS2="${D}  ${S_ARR} ${R}"
  PROMPT_DIRTRIM=3
}

eqx_prompt_command() {
  local ec=$?
  history -a 2>/dev/null
  eqx_build_prompt "$ec"
  return $ec
}

# =============================================================================
# 8. ALIAS, FUNGSI SHELL, KOMPLESI
# =============================================================================
eqx_define_aliases() {
  alias ls='ls --color=auto' 2>/dev/null
  alias ll='ls -lAh --color=auto'
  alias la='ls -A --color=auto'
  alias l='ls -CF --color=auto'
  alias lt='ls -lAht --color=auto'
  alias ..='cd ..'
  alias ...='cd ../..'
  alias ....='cd ../../..'
  alias ~='cd ~'
  alias -- -='cd -'
  alias cls='clear'
  alias c='clear'
  alias h='history'
  alias grep='grep --color=auto'
  alias egrep='grep -E --color=auto'
  alias fgrep='grep -F --color=auto'
  alias df='df -h'
  alias du='du -h'
  alias free='free -h'
  alias path='echo -e "${PATH//:/\\n}"'
  alias now='date "+%A, %d %B %Y  %H:%M:%S"'
  alias cp='cp -i'
  alias mv='mv -i'
  alias mkdir='mkdir -p'
  alias myip='eqx ip'
  alias ports='eqx ports'
  alias pkgup='eqx pkg upgrade'
  alias reload='eqx reload'
  alias q='exit'
  alias e='eqx'
  [[ -f "$EQX_ALIAS_FILE" ]] && source "$EQX_ALIAS_FILE"
  return 0
}

eqx_define_functions() {
  mkcd() { [[ $# -eq 1 ]] || { echo "pakai: mkcd <direktori>"; return 1; }; mkdir -p -- "$1" && cd -- "$1" || return; }
  up() {
    local n="${1:-1}" p=""
    [[ "$n" =~ ^[0-9]+$ ]] || n=1
    while (( n-- > 0 )); do p+="../"; done
    cd "${p:-.}" || return
  }
  bak() {
    local f
    for f in "$@"; do cp -a -- "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)" && echo "dibackup: $f"; done
  }
  psg() { ps aux 2>/dev/null | grep -i -- "${1:?pakai: psg <pola>}" | grep -v 'grep -i'; }
  hg() { history | grep -i -- "${*:?pakai: hg <kata>}"; }
  cheat() { curl -fsS --max-time 10 "https://cheat.sh/${1:?pakai: cheat <perintah>}"; }
  extract() { eqx_cmd_extract "$@"; }
  eqx() { eqx_main "$@"; }
  equinox() { eqx_main "$@"; }
  return 0
}

# Komplesi tab untuk `eqx`
_eqx_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" cmd="${COMP_WORDS[1]:-}" subs
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "${EQX_CMDLIST[*]} help version" -- "$cur") )
    return 0
  fi
  cmd="${EQX_CMD_ALIAS[$cmd]:-$cmd}"
  subs="${EQX_CMD_SUBS[$cmd]:-}"
  if [[ -n "$subs" && $COMP_CWORD -eq 2 ]]; then
    COMPREPLY=( $(compgen -W "$subs" -- "$cur") )
  else
    COMPREPLY=( $(compgen -f -- "$cur") )
  fi
  return 0
}

# =============================================================================
# 9. INFORMASI SISTEM
# =============================================================================
eqx_os_name() {
  if (( EQX_IS_TERMUX )); then
    local av; av="$(getprop ro.build.version.release 2>/dev/null)"
    printf 'Android %s (Termux)' "${av:-?}"
  elif [[ -r /etc/os-release ]]; then
    ( . /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}" )
  else
    uname -s
  fi
}

eqx_device_name() {
  local mf md
  if eqx_have getprop; then
    mf="$(getprop ro.product.manufacturer 2>/dev/null)"
    md="$(getprop ro.product.model 2>/dev/null)"
    [[ -n "$mf$md" ]] && { printf '%s %s' "$mf" "$md"; return; }
  fi
  if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
    cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null; return
  fi
  uname -n
}

eqx_uptime_secs() {
  local u=""
  if [[ -r /proc/uptime ]]; then read -r u _ 2>/dev/null </proc/uptime; fi
  if [[ -n "$u" ]]; then printf '%s' "${u%.*}"; return; fi
  local up; up="$(uptime -s 2>/dev/null)"
  if [[ -n "$up" ]]; then printf '%s' "$(( $(date +%s) - $(date -d "$up" +%s 2>/dev/null || echo "$(date +%s)") ))"; return; fi
  printf '0'
}

eqx_cpu_name() {
  local n=""
  if [[ -r /proc/cpuinfo ]]; then
    n="$(grep -m1 -E '^(model name|Hardware|Processor)' /proc/cpuinfo 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//')"
  fi
  if [[ -z "$n" ]] && eqx_have getprop; then
    n="$(getprop ro.soc.model 2>/dev/null)"
    [[ -z "$n" ]] && n="$(getprop ro.board.platform 2>/dev/null)"
  fi
  printf '%s' "${n:-$EQX_ARCH}"
}

eqx_cpu_cores() {
  local n
  n="$(nproc 2>/dev/null)" || n=""
  [[ -z "$n" && -r /proc/cpuinfo ]] && n="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
  printf '%s' "${n:-1}"
}

# Isi: EQX_MEM_TOTAL EQX_MEM_USED EQX_MEM_AVAIL EQX_SWAP_TOTAL EQX_SWAP_USED (kB)
eqx_meminfo() {
  local k v
  local -A m=()
  EQX_MEM_TOTAL=0; EQX_MEM_USED=0; EQX_MEM_AVAIL=0; EQX_SWAP_TOTAL=0; EQX_SWAP_USED=0
  [[ -r /proc/meminfo ]] || return 1
  while read -r k v _; do m["${k%:}"]="$v"; done </proc/meminfo
  EQX_MEM_TOTAL="${m[MemTotal]:-0}"
  EQX_MEM_AVAIL="${m[MemAvailable]:-$(( ${m[MemFree]:-0} + ${m[Cached]:-0} ))}"
  EQX_MEM_USED=$(( EQX_MEM_TOTAL - EQX_MEM_AVAIL ))
  EQX_SWAP_TOTAL="${m[SwapTotal]:-0}"
  EQX_SWAP_USED=$(( EQX_SWAP_TOTAL - ${m[SwapFree]:-0} ))
  EQX_MEM_BUFFERS="${m[Buffers]:-0}"; EQX_MEM_CACHED="${m[Cached]:-0}"; EQX_MEM_FREE="${m[MemFree]:-0}"
  (( EQX_MEM_TOTAL > 0 ))
}

# Isi: EQX_DISK_TOTAL EQX_DISK_USED EQX_DISK_FREE (kB) EQX_DISK_PCT
eqx_disk_stat() { # [path]
  local p="${1:-$HOME}" t u f pc
  read -r t u f pc < <(df -Pk "$p" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $2,$3,$4,$5}')
  EQX_DISK_TOTAL="${t:-0}"; EQX_DISK_USED="${u:-0}"; EQX_DISK_FREE="${f:-0}"; EQX_DISK_PCT="${pc:-0}"
  (( EQX_DISK_TOTAL > 0 ))
}

# Isi: EQX_BAT_PCT EQX_BAT_STATUS
eqx_battery_read() {
  EQX_BAT_PCT=""; EQX_BAT_STATUS=""
  local j f
  if eqx_have termux-battery-status; then
    j="$(timeout 4 termux-battery-status 2>/dev/null)"
    if [[ -n "$j" ]]; then
      [[ "$j" =~ \"percentage\":[[:space:]]*([0-9]+) ]] && EQX_BAT_PCT="${BASH_REMATCH[1]}"
      [[ "$j" =~ \"status\":[[:space:]]*\"([A-Za-z_]+)\" ]] && EQX_BAT_STATUS="${BASH_REMATCH[1]}"
    fi
  fi
  if [[ -z "$EQX_BAT_PCT" ]]; then
    for f in /sys/class/power_supply/battery /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
      if [[ -r "$f/capacity" ]]; then
        read -r EQX_BAT_PCT <"$f/capacity" 2>/dev/null
        [[ -r "$f/status" ]] && read -r EQX_BAT_STATUS <"$f/status" 2>/dev/null
        break
      fi
    done
  fi
  [[ "$EQX_BAT_PCT" =~ ^[0-9]+$ ]]
}

eqx_pkg_count() {
  case "$EQX_PKGMGR" in
    pkg|apt) dpkg-query -f '.\n' -W 2>/dev/null | wc -l ;;
    pacman)  pacman -Qq 2>/dev/null | wc -l ;;
    dnf|zypper) rpm -qa 2>/dev/null | wc -l ;;
    apk)     apk info 2>/dev/null | wc -l ;;
    *)       echo "?" ;;
  esac
}

eqx_local_ip() {
  local ip=""
  if eqx_have ip; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)"
    [[ -z "$ip" ]] && ip="$(ip -4 addr show 2>/dev/null | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | grep -v '^127\.' | head -n1)"
  fi
  if [[ -z "$ip" ]] && eqx_have ifconfig; then
    ip="$(ifconfig 2>/dev/null | sed -n 's/.*inet \(addr:\)\{0,1\}\([0-9.]*\).*/\2/p' | grep -v '^127\.' | head -n1)"
  fi
  [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "${ip:--}"
}

eqx_public_ip() {
  eqx_have curl || return 1
  local u ip
  for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip="$(curl -fsS --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]')"
    [[ "$ip" =~ ^[0-9a-fA-F:.]{3,45}$ ]] && { printf '%s' "$ip"; return 0; }
  done
  return 1
}

eqx_cmd_info() {
  eqx_logo
  printf '  %s%s%s\n\n' "$C_D" "Linux Terminal untuk Termux  -  v$EQX_VERSION \"$EQX_CODENAME\"" "$C_R"
  local up mem="-" disk="-" bat="-" ip
  up="$(eqx_dur "$(eqx_uptime_secs)")"
  eqx_meminfo && mem="$(eqx_human_kb "$EQX_MEM_USED") / $(eqx_human_kb "$EQX_MEM_TOTAL")"
  eqx_disk_stat "$HOME" && disk="$(eqx_human_kb "$EQX_DISK_USED") / $(eqx_human_kb "$EQX_DISK_TOTAL") (${EQX_DISK_PCT}%)"
  eqx_battery_read && bat="${EQX_BAT_PCT}%${EQX_BAT_STATUS:+ ($EQX_BAT_STATUS)}"
  ip="$(eqx_local_ip)"
  eqx_kv "OS" "$(eqx_os_name)"
  eqx_kv "Perangkat" "$(eqx_device_name)"
  eqx_kv "Kernel" "$EQX_KERNEL"
  eqx_kv "Arsitektur" "$EQX_ARCH"
  eqx_kv "CPU" "$(eqx_cpu_name) ($(eqx_cpu_cores) inti)"
  eqx_kv "Memori" "$mem"
  eqx_kv "Disk" "$disk"
  eqx_kv "Baterai" "$bat"
  eqx_kv "Uptime" "$up"
  eqx_kv "Shell" "bash $BASH_VERSION"
  eqx_kv "Paket" "$(eqx_pkg_count) ($EQX_PKGMGR)"
  eqx_kv "IP lokal" "$ip"
  eqx_kv "Tema" "$EQX_THEME_NAME"
  local i
  printf '\n  '
  for i in 16 17 18 19 20 21 196 202 208 214 220 226 46 49 51 39 33 129 201; do
    (( EQX_COLOR )) && printf '\e[48;5;%sm  \e[0m' "$i" || printf '[]'
  done
  printf '\n'
}

eqx_cmd_sys() {
  eqx_title "Informasi Sistem Lengkap"
  eqx_section "Platform"
  eqx_kv "OS" "$(eqx_os_name)" 13
  eqx_kv "Perangkat" "$(eqx_device_name)" 13
  eqx_kv "Kernel" "$EQX_KERNEL" 13
  eqx_kv "Arsitektur" "$EQX_ARCH" 13
  eqx_kv "Hostname" "$(hostname 2>/dev/null || uname -n)" 13
  eqx_kv "Pengguna" "$(id -un 2>/dev/null) (uid $(id -u 2>/dev/null))" 13
  eqx_kv "Termux" "$( (( EQX_IS_TERMUX )) && echo "ya (${TERMUX_VERSION:-versi tidak diketahui})" || echo tidak )" 13
  eqx_section "Prosesor"
  eqx_kv "Model" "$(eqx_cpu_name)" 13
  eqx_kv "Jumlah inti" "$(eqx_cpu_cores)" 13
  if [[ -r /proc/loadavg ]]; then eqx_kv "Load average" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)" 13; fi
  local f="/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
  [[ -r "$f" ]] && eqx_kv "Frekuensi cpu0" "$(( $(cat "$f") / 1000 )) MHz" 13
  eqx_section "Lingkungan"
  eqx_kv "Shell" "$BASH ($BASH_VERSION)" 13
  eqx_kv "TERM" "${TERM:-?}" 13
  eqx_kv "Ukuran layar" "$(eqx_cols)x$(eqx_rows)" 13
  eqx_kv "LANG" "${LANG:-(kosong)}" 13
  eqx_kv "HOME" "$HOME" 13
  eqx_kv "PREFIX" "${PREFIX:--}" 13
  eqx_kv "Zona waktu" "$(date +%Z) ($(date +%z))" 13
  eqx_kv "Tanggal" "$(date '+%A, %d %B %Y %H:%M:%S')" 13
  eqx_kv "Uptime" "$(eqx_dur "$(eqx_uptime_secs)")" 13
  eqx_kv "Pkg manager" "$EQX_PKGMGR" 13
  eqx_section "Penyimpanan & memori"
  eqx_cmd_mem
}

eqx_cmd_mem() {
  if ! eqx_meminfo; then eqx_warn "tidak dapat membaca /proc/meminfo"; return 1; fi
  local pct=$(( EQX_MEM_USED * 100 / EQX_MEM_TOTAL ))
  printf '  %sRAM   %s  ' "$C_A" "$C_R"; eqx_bar "$pct" 24
  printf '  %s / %s\n' "$(eqx_human_kb "$EQX_MEM_USED")" "$(eqx_human_kb "$EQX_MEM_TOTAL")"
  if (( EQX_SWAP_TOTAL > 0 )); then
    pct=$(( EQX_SWAP_USED * 100 / EQX_SWAP_TOTAL ))
    printf '  %sSwap  %s  ' "$C_A" "$C_R"; eqx_bar "$pct" 24
    printf '  %s / %s\n' "$(eqx_human_kb "$EQX_SWAP_USED")" "$(eqx_human_kb "$EQX_SWAP_TOTAL")"
  fi
  eqx_kv "Tersedia" "$(eqx_human_kb "$EQX_MEM_AVAIL")"
  eqx_kv "Bebas" "$(eqx_human_kb "$EQX_MEM_FREE")"
  eqx_kv "Cache" "$(eqx_human_kb "$EQX_MEM_CACHED")"
  eqx_kv "Buffers" "$(eqx_human_kb "$EQX_MEM_BUFFERS")"
}

eqx_cmd_battery() {
  if ! eqx_battery_read; then
    eqx_warn "info baterai tidak tersedia."
    (( EQX_IS_TERMUX )) && eqx_dim "  Pasang: pkg install termux-api  + aplikasi Termux:API dari F-Droid."
    return 1
  fi
  printf '  %sBaterai%s  ' "$C_A" "$C_R"
  local col="$C_OK"
  (( EQX_BAT_PCT <= 20 )) && col="$C_E"
  (( EQX_BAT_PCT > 20 && EQX_BAT_PCT <= 50 )) && col="$C_W"
  local f=$(( EQX_BAT_PCT * 24 / 100 )) fs es
  printf -v fs '%*s' "$f" ''; printf -v es '%*s' "$(( 24 - f ))" ''
  printf '%s%s%s%s %d%%\n' "$col" "${fs// /$S_FULL}" "$C_D" "${es// /$S_EMPTY}$C_R" "$EQX_BAT_PCT"
  [[ -n "$EQX_BAT_STATUS" ]] && eqx_kv "Status" "$EQX_BAT_STATUS"
  if eqx_have termux-battery-status; then
    local j; j="$(timeout 4 termux-battery-status 2>/dev/null)"
    [[ "$j" =~ \"temperature\":[[:space:]]*([0-9.]+) ]] && eqx_kv "Suhu" "${BASH_REMATCH[1]} °C"
    [[ "$j" =~ \"health\":[[:space:]]*\"([A-Za-z_]+)\" ]] && eqx_kv "Kesehatan" "${BASH_REMATCH[1]}"
    [[ "$j" =~ \"plugged\":[[:space:]]*\"([A-Za-z_]+)\" ]] && eqx_kv "Daya" "${BASH_REMATCH[1]}"
  fi
}

eqx_cmd_storage() {
  eqx_title "Penyimpanan"
  local p
  for p in "$HOME" "${PREFIX:-}" /sdcard /storage/emulated/0 /tmp; do
    [[ -n "$p" && -d "$p" ]] || continue
    eqx_disk_stat "$p" || continue
    printf '  %s%-22s%s ' "$C_A" "$p" "$C_R"
    eqx_bar "$EQX_DISK_PCT" 18
    printf '  %s bebas dari %s\n' "$(eqx_human_kb "$EQX_DISK_FREE")" "$(eqx_human_kb "$EQX_DISK_TOTAL")"
  done
  eqx_section "Folder terbesar di $HOME"
  eqx_cmd_usage "$HOME" 8
}

eqx_cmd_proc() { # [jumlah] [mem|cpu]
  local n="${1:-10}" by="${2:-mem}" key="-pmem"
  [[ "$n" =~ ^[0-9]+$ ]] || n=10
  [[ "$by" == cpu ]] && key="-pcpu"
  if ps -eo pid,pcpu,pmem,etime,comm --sort="$key" >/dev/null 2>&1; then
    ps -eo pid,pcpu,pmem,etime,comm --sort="$key" 2>/dev/null | head -n $(( n + 1 ))
  elif ps aux >/dev/null 2>&1; then
    ps aux 2>/dev/null | head -n $(( n + 1 ))
  else
    ps 2>/dev/null | head -n $(( n + 1 ))
  fi
}

eqx_cmd_monitor() { # [interval]
  local iv="${1:-2}" key="" pct
  [[ "$iv" =~ ^[0-9]+$ ]] && (( iv >= 1 )) || iv=2
  eqx_screen_enter
  while (( ! EQX_STOP )); do
    printf '\033[H'
    eqx_line "${C_B}${C_P} EQUINOX MONITOR ${C_R}${C_D} $(date '+%H:%M:%S')  -  tekan q untuk keluar${C_R}"
    eqx_line ""
    eqx_line "  ${C_A}Uptime${C_R}   $(eqx_dur "$(eqx_uptime_secs)")"
    [[ -r /proc/loadavg ]] && eqx_line "  ${C_A}Load   ${C_R}   $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
    if eqx_meminfo; then
      pct=$(( EQX_MEM_USED * 100 / EQX_MEM_TOTAL ))
      eqx_line "  ${C_A}RAM    ${C_R}   $(eqx_bar "$pct" 22)  $(eqx_human_kb "$EQX_MEM_USED")/$(eqx_human_kb "$EQX_MEM_TOTAL")"
    fi
    if eqx_disk_stat "$HOME"; then
      eqx_line "  ${C_A}Disk   ${C_R}   $(eqx_bar "$EQX_DISK_PCT" 22)  $(eqx_human_kb "$EQX_DISK_FREE") bebas"
    fi
    if eqx_battery_read; then
      eqx_line "  ${C_A}Baterai${C_R}   $(eqx_bar "$EQX_BAT_PCT" 22)  ${EQX_BAT_STATUS}"
    fi
    eqx_line ""
    eqx_line "  ${C_B}Proses teratas (memori)${C_R}"
    local l
    while IFS= read -r l; do eqx_line "  ${C_D}${l:0:$(( $(eqx_cols) - 4 ))}${C_R}"; done < <(eqx_cmd_proc 8 mem 2>/dev/null)
    printf '\033[J'
    if read -rsn1 -t "$iv" key; then [[ "$key" == q || "$key" == Q ]] && break; fi
  done
  eqx_screen_leave
}

eqx_cmd_clock() {
  local key=""
  eqx_screen_enter
  while (( ! EQX_STOP )); do
    printf '\033[H\n'
    eqx_bigtext "$(date +%H:%M:%S)"
    eqx_line ""
    eqx_line "  ${C_D}$(date '+%A, %d %B %Y')  -  tekan q untuk keluar${C_R}"
    printf '\033[J'
    if read -rsn1 -t 0.5 key; then [[ "$key" == q || "$key" == Q ]] && break; fi
  done
  eqx_screen_leave
}

eqx_cmd_uptime() {
  local s; s="$(eqx_uptime_secs)"
  eqx_kv "Uptime" "$(eqx_dur "$s")"
  eqx_kv "Menyala sejak" "$(date -d "@$(( $(date +%s) - s ))" '+%d %B %Y %H:%M' 2>/dev/null || echo '-')"
}

eqx_cmd_doctor() {
  eqx_title "Equinox Doctor"
  local ok=0 miss=0 optmiss=0 c pkgname
  local -a missing_pkgs=()
  eqx_section "Perintah wajib"
  local -A req=( [bash]=bash [curl]=curl [awk]=gawk [sed]=sed [grep]=grep [find]=findutils [tar]=tar
                 [gzip]=gzip [tput]=ncurses-utils [ps]=procps [date]=coreutils [sort]=coreutils [timeout]=coreutils )
  for c in bash curl awk sed grep find tar gzip tput ps date sort timeout; do
    if eqx_have "$c"; then
      printf '  %s%s%s %-10s %s\n' "$C_OK" "$S_OK" "$C_R" "$c" "$C_D$(command -v "$c")$C_R"; ok=$(( ok + 1 ))
    else
      printf '  %s%s%s %-10s %sTIDAK ADA%s\n' "$C_E" "$S_ERR" "$C_R" "$c" "$C_E" "$C_R"; miss=$(( miss + 1 ))
      missing_pkgs+=("${req[$c]}")
    fi
  done
  eqx_section "Perintah opsional"
  local -A opt=( [git]=git [nano]=nano [vim]=vim [python3]=python [openssl]=openssl-tool [jq]=jq
                 [ping]=inetutils [dig]=dnsutils [zip]=zip [unzip]=unzip [termux-battery-status]=termux-api [tree]=tree )
  for c in git nano vim python3 openssl jq ping dig zip unzip termux-battery-status tree; do
    if eqx_have "$c"; then
      printf '  %s%s%s %s\n' "$C_OK" "$S_OK" "$C_R" "$c"
    else
      printf '  %s%s%s %-22s %s(opsional)%s\n' "$C_W" "$S_WARN" "$C_R" "$c" "$C_D" "$C_R"; optmiss=$(( optmiss + 1 ))
    fi
  done
  eqx_section "Lingkungan"
  eqx_kv "Bash" "$BASH_VERSION" 14
  eqx_kv "Termux" "$( (( EQX_IS_TERMUX )) && echo ya || echo tidak )" 14
  eqx_kv "Pkg manager" "$EQX_PKGMGR" 14
  eqx_kv "Folder Equinox" "$EQX_HOME" 14
  eqx_kv "Dapat ditulis" "$( [[ -w "$EQX_HOME" ]] && echo ya || echo TIDAK )" 14
  eqx_kv "File inti" "$EQX_SELF" 14
  eqx_kv "Direktori tmp" "$(eqx_tmpdir)" 14
  if eqx_have curl; then
    if curl -fsS --max-time 6 -o /dev/null https://github.com 2>/dev/null; then
      eqx_kv "Internet" "${C_OK}terhubung${C_R}" 14
    else
      eqx_kv "Internet" "${C_W}tidak terjangkau${C_R}" 14
    fi
  fi
  printf '\n'
  if (( miss == 0 )); then
    eqx_ok "Semua perintah wajib tersedia ($ok). Opsional hilang: $optmiss."
  else
    eqx_err "$miss perintah wajib hilang."
    local uniq; uniq="$(printf '%s\n' "${missing_pkgs[@]}" | sort -u | tr '\n' ' ')"
    eqx_info "Perbaiki dengan: eqx pkg install $uniq"
    return 1
  fi
}

eqx_cmd_env() {
  eqx_title "Lingkungan Equinox"
  eqx_kv "Versi" "$EQX_VERSION ($EQX_CODENAME)" 16
  eqx_kv "EQX_HOME" "$EQX_HOME" 16
  eqx_kv "EQX_LIB" "$EQX_LIB" 16
  eqx_kv "File config" "$EQX_CONF" 16
  eqx_kv "File log" "$EQX_LOGFILE" 16
  eqx_kv "Plugin" "$EQX_PLUGIN_DIR" 16
  eqx_kv "Backup" "$EQX_BACKUP_DIR" 16
  eqx_kv "Tempat sampah" "$EQX_TRASH_DIR" 16
  eqx_kv "Shell" "$BASH" 16
  eqx_kv "Interaktif" "$( [[ $- == *i* ]] && echo ya || echo tidak )" 16
  eqx_kv "Warna" "$( (( EQX_COLOR )) && echo aktif || echo mati )" 16
  eqx_kv "Unicode" "$( (( EQX_UNI )) && echo aktif || echo mati )" 16
  eqx_kv "PATH" "$PATH" 16
  if [[ -f "$EQX_META" ]]; then
    eqx_section "Metadata instalasi"
    sed 's/^/  /' "$EQX_META"
  fi
}

# =============================================================================
# 10. JARINGAN
# =============================================================================
eqx_cmd_ip() { # [geo]
  local sub="${1:-}" pub
  if [[ "$sub" == geo ]]; then
    eqx_need curl || return 1
    local j
    j="$(curl -fsS --max-time 8 https://ipinfo.io/json 2>/dev/null)" || { eqx_err "gagal menghubungi ipinfo.io"; return 1; }
    local k v
    for k in ip hostname city region country org loc timezone; do
      v="$(grep -o "\"$k\": *\"[^\"]*\"" <<<"$j" | head -n1 | sed 's/^[^:]*: *"//; s/"$//')"
      [[ -n "$v" ]] && eqx_kv "$k" "$v" 10
    done
    return 0
  fi
  eqx_title "Alamat IP"
  eqx_kv "IP lokal" "$(eqx_local_ip)" 11
  if pub="$(eqx_public_ip)"; then eqx_kv "IP publik" "$pub" 11; else eqx_kv "IP publik" "${C_W}tidak terjangkau${C_R}" 11; fi
  eqx_kv "Hostname" "$(hostname 2>/dev/null || uname -n)" 11
  eqx_dim "  Detail lokasi/ISP: eqx ip geo"
}

eqx_cmd_net() {
  eqx_title "Tes Koneksi"
  eqx_need curl || return 1
  local t code
  local -a targets=("https://www.gstatic.com/generate_204|Google" "https://1.1.1.1|Cloudflare" "https://github.com|GitHub" "https://raw.githubusercontent.com|GitHub Raw")
  local item url name
  for item in "${targets[@]}"; do
    url="${item%%|*}"; name="${item##*|}"
    t="$(curl -fsS -o /dev/null -w '%{http_code} %{time_total}' --max-time 8 "$url" 2>/dev/null)" || t=""
    if [[ -n "$t" ]]; then
      code="${t%% *}"
      printf '  %s%s%s %-14s HTTP %s  %s detik\n' "$C_OK" "$S_OK" "$C_R" "$name" "$code" "${t##* }"
    else
      printf '  %s%s%s %-14s %sgagal%s\n' "$C_E" "$S_ERR" "$C_R" "$name" "$C_E" "$C_R"
    fi
  done
  eqx_kv "IP lokal" "$(eqx_local_ip)" 11
  eqx_kv "Latensi DNS" "$(curl -fsS -o /dev/null -w '%{time_namelookup}s' --max-time 6 https://example.com 2>/dev/null || echo gagal)" 11
}

eqx_cmd_speed() { # [MB]
  eqx_need curl || return 1
  local mb="${1:-10}" r sp tt sz
  [[ "$mb" =~ ^[0-9]+$ ]] && (( mb >= 1 && mb <= 200 )) || mb=10
  eqx_info "Mengunduh ${mb} MB dari speed.cloudflare.com ..."
  r="$(curl -fsS -o /dev/null --max-time 90 -w '%{speed_download} %{time_total} %{size_download}' "https://speed.cloudflare.com/__down?bytes=$(( mb * 1000000 ))" 2>/dev/null)" \
    || { eqx_err "tes kecepatan gagal (cek koneksi)"; return 1; }
  read -r sp tt sz <<<"$r"
  awk -v s="$sp" -v t="$tt" -v z="$sz" 'BEGIN{printf "  Unduhan : %.2f Mbps (%.2f MB/s)\n  Waktu   : %.2f detik\n  Ukuran  : %.1f MB\n", s*8/1000000, s/1000000, t, z/1000000}'
}

eqx_cmd_ping() { # host [jumlah]
  local host="${1:-1.1.1.1}" n="${2:-4}"
  [[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]] || { eqx_err "host tidak valid"; return 1; }
  [[ "$n" =~ ^[0-9]+$ ]] || n=4
  if eqx_have ping; then
    ping -c "$n" "$host"
  else
    eqx_need curl || return 1
    eqx_warn "perintah ping tidak ada, memakai pengukuran HTTP via curl"
    local i t
    for (( i = 1; i <= n; i++ )); do
      t="$(curl -fsS -o /dev/null -w '%{time_connect}' --max-time 5 "https://$host" 2>/dev/null)" || t="gagal"
      printf '  #%d  %s%s%s\n' "$i" "$C_P" "$t" "$C_R"; sleep 0.5
    done
  fi
}

eqx_cmd_weather() { # [kota|short]
  eqx_need curl || return 1
  local city="${EQX_CFG[WEATHER_CITY]}" mode="full" a
  for a in "$@"; do
    if [[ "$a" == short ]]; then mode="short"; else city="$a"; fi
  done
  [[ "$city" =~ ^[A-Za-z0-9\ ,._+-]*$ ]] || { eqx_err "nama kota tidak valid"; return 1; }
  city="${city// /+}"
  if [[ "$mode" == short ]]; then
    curl -fsS --max-time 10 "https://wttr.in/${city}?format=3&lang=id" || eqx_err "gagal mengambil cuaca"
  else
    curl -fsS --max-time 12 "https://wttr.in/${city}?0&lang=id" || eqx_err "gagal mengambil cuaca"
  fi
  printf '\n'
}

eqx_cmd_headers() { # url
  eqx_need curl || return 1
  local url="${1:-}"
  [[ -n "$url" ]] || { eqx_err "pakai: eqx headers <url>"; return 1; }
  [[ "$url" =~ ^https?:// ]] || url="https://$url"
  curl -sIL --max-time 12 "$url" | sed 's/\r$//'
}

eqx_cmd_dns() { # domain [tipe]
  local host="${1:-}" type="${2:-A}" out
  [[ -n "$host" ]] || { eqx_err "pakai: eqx dns <domain> [A|AAAA|MX|TXT|NS|CNAME]"; return 1; }
  [[ "$host" =~ ^[A-Za-z0-9._-]+$ ]] || { eqx_err "domain tidak valid"; return 1; }
  type="${type^^}"
  [[ "$type" =~ ^(A|AAAA|MX|TXT|NS|CNAME|SOA)$ ]] || { eqx_err "tipe record tidak didukung"; return 1; }
  if eqx_have dig; then dig +short "$host" "$type"; return; fi
  eqx_need curl || return 1
  eqx_dim "  (memakai DNS-over-HTTPS Cloudflare)"
  out="$(curl -fsS --max-time 8 -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=${host}&type=${type}" 2>/dev/null)" \
    || { eqx_err "gagal menghubungi resolver"; return 1; }
  out="$(grep -o '"data":"[^"]*"' <<<"$out" | sed 's/"data":"//; s/"$//')"
  [[ -n "$out" ]] && printf '%s\n' "$out" || eqx_warn "tidak ada record $type untuk $host"
}

eqx_cmd_ports() {
  eqx_info "Port yang sedang listen (milik pengguna ini):"
  if eqx_have ss && ss -tuln 2>/dev/null | grep -q .; then
    ss -tuln 2>/dev/null
  elif eqx_have netstat && netstat -tuln 2>/dev/null | grep -q .; then
    netstat -tuln 2>/dev/null
  else
    eqx_warn "tidak dapat membaca daftar port (Android modern membatasi akses ini)."
    (( EQX_IS_TERMUX )) && eqx_dim "  Coba: pkg install net-tools  lalu  netstat -tuln"
    return 1
  fi
}

eqx_cmd_serve() { # [port] [direktori]
  local port="${1:-8000}" dir="${2:-.}"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )) || { eqx_err "port harus 1024-65535"; return 1; }
  [[ -d "$dir" ]] || { eqx_err "direktori tidak ada: $dir"; return 1; }
  if ! eqx_have python3 && ! eqx_have python; then eqx_err "butuh python: eqx pkg install python"; return 1; fi
  local py; py="$(command -v python3 || command -v python)"
  eqx_ok "Server aktif: http://$(eqx_local_ip):$port  (Ctrl+C untuk berhenti)"
  ( cd "$dir" && "$py" -m http.server "$port" )
}

eqx_cmd_download() { # url [nama-file]
  eqx_need curl || return 1
  local url="${1:-}" out="${2:-}"
  [[ "$url" =~ ^https?:// ]] || { eqx_err "pakai: eqx download <url> [nama-file]"; return 1; }
  [[ -z "$out" ]] && out="$(basename "${url%%\?*}")"
  [[ -z "$out" || "$out" == "/" ]] && out="unduhan.bin"
  eqx_info "Mengunduh ke $out (dapat dilanjutkan jika terputus)"
  curl -fL -C - --retry 3 --progress-bar -o "$out" "$url" && eqx_ok "Selesai: $out ($(eqx_human "$(wc -c <"$out")"))"
}

# =============================================================================
# 11. BERKAS & DIREKTORI
# =============================================================================
eqx_cmd_usage() { # [dir] [jumlah]
  local dir="${1:-.}" n="${2:-15}" line sz name max=0
  [[ -d "$dir" ]] || { eqx_err "bukan direktori: $dir"; return 1; }
  [[ "$n" =~ ^[0-9]+$ ]] || n=15
  local -a rows=()
  while IFS=$'\t' read -r sz name; do
    rows+=("$sz"$'\t'"$name")
    (( sz > max )) && max=$sz
  done < <(du -sk -- "$dir"/* "$dir"/.[!.]* 2>/dev/null | sort -rn | head -n "$n")
  (( ${#rows[@]} )) || { eqx_warn "tidak ada isi"; return 0; }
  for line in "${rows[@]}"; do
    sz="${line%%$'\t'*}"; name="${line#*$'\t'}"
    local pct=0; (( max > 0 )) && pct=$(( sz * 100 / max ))
    printf '  %10s  ' "$(eqx_human_kb "$sz")"
    eqx_bar "$pct" 14
    printf '  %s\n' "${name#"$dir"/}"
  done
}

eqx_cmd_big() { # [dir] [jumlah]
  local dir="${1:-.}" n="${2:-15}"
  [[ -d "$dir" ]] || { eqx_err "bukan direktori: $dir"; return 1; }
  [[ "$n" =~ ^[0-9]+$ ]] || n=15
  eqx_info "File terbesar di $dir"
  find "$dir" -xdev -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -n "$n" | while IFS=$'\t' read -r sz name; do
    printf '  %10s  %s\n' "$(eqx_human "$sz")" "$name"
  done
}

eqx_cmd_ff() { # pola [dir]   (cari nama file)
  local pat="${1:-}" dir="${2:-.}"
  [[ -n "$pat" ]] || { eqx_err "pakai: eqx ff <pola-nama> [direktori]"; return 1; }
  find "$dir" -iname "*${pat}*" -not -path '*/.git/*' 2>/dev/null | head -n 200
}

eqx_cmd_sr() { # teks [dir]   (cari isi file)
  local txt="${1:-}" dir="${2:-.}"
  [[ -n "$txt" ]] || { eqx_err "pakai: eqx sr <teks> [direktori]"; return 1; }
  if eqx_have rg; then rg -n --color=auto -- "$txt" "$dir" | head -n 300
  else grep -rIn --color=auto --exclude-dir=.git -- "$txt" "$dir" 2>/dev/null | head -n 300; fi
}

eqx__tree_walk() { # dir prefix depth maxdepth
  local dir="$1" prefix="$2" depth="$3" max="$4" e i=0 total last name
  (( depth > max )) && return 0
  local -a entries=()
  while IFS= read -r e; do entries+=("$e"); done < <(ls -A1 -- "$dir" 2>/dev/null)
  total=${#entries[@]}
  for e in "${entries[@]}"; do
    i=$(( i + 1 )); last=0; (( i == total )) && last=1
    name="$e"
    [[ -d "$dir/$e" ]] && name="${C_P}${e}/${C_R}"
    if (( last )); then printf '%s%s%s %s\n' "$prefix" "$B_BL" "$B_H$B_H" "$name"
    else printf '%s%s%s %s\n' "$prefix" "$B_T" "$B_H$B_H" "$name"; fi
    if [[ -d "$dir/$e" && ! -L "$dir/$e" ]]; then
      if (( last )); then eqx__tree_walk "$dir/$e" "$prefix    " $(( depth + 1 )) "$max"
      else eqx__tree_walk "$dir/$e" "${prefix}$B_V   " $(( depth + 1 )) "$max"; fi
    fi
  done
}

eqx_cmd_tree() { # [dir] [kedalaman]
  local dir="${1:-.}" max="${2:-2}"
  [[ -d "$dir" ]] || { eqx_err "bukan direktori: $dir"; return 1; }
  [[ "$max" =~ ^[0-9]+$ ]] || max=2
  if eqx_have tree; then tree -L "$max" -C "$dir"; return; fi
  printf '%s%s%s\n' "$C_P" "$dir" "$C_R"
  eqx__tree_walk "$dir" "" 1 "$max"
}

eqx_cmd_extract() { # arsip...
  [[ $# -ge 1 ]] || { eqx_err "pakai: eqx extract <arsip> [arsip2 ...]"; return 1; }
  local f rc=0
  for f in "$@"; do
    [[ -f "$f" ]] || { eqx_err "tidak ada: $f"; rc=1; continue; }
    eqx_info "Mengekstrak $f"
    case "${f,,}" in
      *.tar.gz|*.tgz)   tar -xzf "$f" ;;
      *.tar.bz2|*.tbz2) tar -xjf "$f" ;;
      *.tar.xz|*.txz)   tar -xJf "$f" ;;
      *.tar)            tar -xf "$f" ;;
      *.zip)            eqx_need unzip unzip && unzip -q "$f" ;;
      *.gz)             gunzip -k -- "$f" ;;
      *.bz2)            bunzip2 -k -- "$f" ;;
      *.xz)             unxz -k -- "$f" ;;
      *.7z)             if eqx_have 7z; then 7z x "$f"; elif eqx_have 7za; then 7za x "$f"; else eqx_err "butuh p7zip: eqx pkg install p7zip"; false; fi ;;
      *.rar)            if eqx_have unrar; then unrar x "$f"; else eqx_err "butuh unrar"; false; fi ;;
      *) eqx_err "format tidak dikenal: $f"; false ;;
    esac || rc=1
  done
  return $rc
}

eqx_cmd_pack() { # nama.(tar.gz|zip|tar.xz) berkas...
  local out="${1:-}"; shift || true
  [[ -n "$out" && $# -ge 1 ]] || { eqx_err "pakai: eqx pack <nama.tar.gz|nama.zip|nama.tar.xz> <berkas...>"; return 1; }
  case "${out,,}" in
    *.tar.gz|*.tgz) tar -czf "$out" "$@" ;;
    *.tar.xz)       tar -cJf "$out" "$@" ;;
    *.tar.bz2)      tar -cjf "$out" "$@" ;;
    *.zip)          eqx_need zip zip || return 1; zip -qr "$out" "$@" ;;
    *) eqx_err "ekstensi harus .tar.gz, .tar.xz, .tar.bz2, atau .zip"; return 1 ;;
  esac && eqx_ok "Dibuat: $out ($(eqx_human "$(wc -c <"$out")"))"
}

eqx_cmd_backup() { # create|list|restore|prune
  local sub="${1:-create}"; [[ $# -gt 0 ]] && shift
  mkdir -p "$EQX_BACKUP_DIR"
  case "$sub" in
    create)
      local src="${1:-$HOME}" name stamp out
      [[ -e "$src" ]] || { eqx_err "tidak ada: $src"; return 1; }
      src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
      name="$(basename "$src")"; stamp="$(date +%Y%m%d-%H%M%S)"
      out="$EQX_BACKUP_DIR/${name}-${stamp}.tar.gz"
      eqx_info "Mencadangkan $src ..."
      if tar -czf "$out" --exclude='.equinox/backups' --exclude='.equinox/cache' --exclude='.equinox/trash' \
           --exclude='.cache' --exclude='.npm' --exclude='storage' -C "$(dirname "$src")" "$name" 2>/dev/null; then
        eqx_ok "Backup: $out ($(eqx_human "$(wc -c <"$out")"))"
      else
        eqx_err "backup gagal"; rm -f "$out"; return 1
      fi ;;
    list)
      local f any=0
      for f in "$EQX_BACKUP_DIR"/*.tar.gz; do
        [[ -e "$f" ]] || continue; any=1
        printf '  %10s  %s\n' "$(eqx_human "$(wc -c <"$f")")" "$(basename "$f")"
      done
      (( any )) || eqx_dim "  (belum ada backup)" ;;
    restore)
      local f="${1:-}" dest="${2:-.}"
      [[ -n "$f" ]] || { eqx_err "pakai: eqx backup restore <file> [tujuan]"; return 1; }
      [[ -f "$f" ]] || f="$EQX_BACKUP_DIR/$f"
      [[ -f "$f" ]] || { eqx_err "file backup tidak ditemukan"; return 1; }
      mkdir -p "$dest"
      eqx_confirm "Ekstrak $(basename "$f") ke $dest ?" n || { eqx_info "dibatalkan"; return 0; }
      tar -xzf "$f" -C "$dest" && eqx_ok "Dipulihkan ke $dest" ;;
    prune)
      local keep="${1:-5}" i=0 f
      [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
      while IFS= read -r f; do
        i=$(( i + 1 ))
        (( i > keep )) && { rm -f -- "$f"; eqx_info "hapus $(basename "$f")"; }
      done < <(ls -1t "$EQX_BACKUP_DIR"/*.tar.gz 2>/dev/null)
      eqx_ok "Menyisakan $keep backup terbaru" ;;
    *) eqx_err "subperintah: create | list | restore | prune"; return 1 ;;
  esac
}

eqx_cmd_dups() { # [dir]
  local dir="${1:-.}" t1 t2 sizes
  [[ -d "$dir" ]] || { eqx_err "bukan direktori: $dir"; return 1; }
  eqx_info "Mencari file duplikat di $dir ..."
  t1="$(eqx_tmpfile)"; t2="$(eqx_tmpfile)"
  find "$dir" -type f -size +0c -printf '%s\t%p\n' 2>/dev/null | sort -n >"$t1"
  sizes="$(cut -f1 "$t1" | uniq -d)"
  if [[ -z "$sizes" ]]; then eqx_ok "Tidak ada duplikat."; rm -f "$t1" "$t2"; return 0; fi
  awk -F'\t' 'NR==FNR{d[$1]=1;next} ($1 in d){print $2}' <(printf '%s\n' "$sizes") "$t1" \
    | tr '\n' '\0' | xargs -0 md5sum 2>/dev/null | sort | uniq -w32 -D >"$t2"
  if [[ ! -s "$t2" ]]; then eqx_ok "Tidak ada duplikat."; rm -f "$t1" "$t2"; return 0; fi
  awk -v c="$C_A" -v r="$C_R" '{h=$1; if(h!=last){if(NR>1)print ""; printf "%s%s grup %d%s\n", c, "*", ++g, r; last=h}
    sub(/^[^ ]+  /,""); print "   " $0} END{print ""; print g " grup duplikat ditemukan."}' "$t2"
  rm -f "$t1" "$t2"
}

eqx_cmd_trash() { # put|list|restore|empty
  local sub="${1:-list}"; [[ $# -gt 0 ]] && shift
  mkdir -p "$EQX_TRASH_DIR"
  case "$sub" in
    put|rm)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx trash put <berkas...>"; return 1; }
      local f id base
      for f in "$@"; do
        [[ -e "$f" || -L "$f" ]] || { eqx_warn "tidak ada: $f"; continue; }
        base="$(basename "$f")"; id="$(date +%s)-$RANDOM"
        mkdir -p "$EQX_TRASH_DIR/$id"
        printf '%s\n' "$(cd "$(dirname "$f")" && pwd)/$base" >"$EQX_TRASH_DIR/$id/.origin"
        mv -- "$f" "$EQX_TRASH_DIR/$id/$base" && eqx_ok "dipindah ke tempat sampah: $f"
      done ;;
    list|ls)
      local d any=0 o
      for d in "$EQX_TRASH_DIR"/*/; do
        [[ -d "$d" ]] || continue; any=1
        o="$(cat "$d/.origin" 2>/dev/null)"
        printf '  %s%s%s  %s\n' "$C_A" "$(basename "$d")" "$C_R" "$o"
      done
      (( any )) || eqx_dim "  (tempat sampah kosong)" ;;
    restore)
      local id="${1:-}" d origin
      [[ -n "$id" && -d "$EQX_TRASH_DIR/$id" ]] || { eqx_err "pakai: eqx trash restore <id>  (lihat: eqx trash list)"; return 1; }
      d="$EQX_TRASH_DIR/$id"; origin="$(cat "$d/.origin" 2>/dev/null)"
      [[ -n "$origin" ]] || { eqx_err "metadata asal hilang"; return 1; }
      [[ -e "$origin" ]] && { eqx_err "sudah ada berkas di $origin"; return 1; }
      mkdir -p "$(dirname "$origin")"
      mv -- "$d/$(basename "$origin")" "$origin" && rm -rf "$d" && eqx_ok "dipulihkan: $origin" ;;
    empty)
      eqx_confirm "Kosongkan tempat sampah secara permanen?" n || { eqx_info "dibatalkan"; return 0; }
      rm -rf "${EQX_TRASH_DIR:?}"/* && eqx_ok "tempat sampah dikosongkan" ;;
    *) eqx_err "subperintah: put | list | restore | empty"; return 1 ;;
  esac
}

eqx_cmd_bm() { # add|go|list|del
  local sub="${1:-list}"; [[ $# -gt 0 ]] && shift
  touch "$EQX_BM_FILE"
  case "$sub" in
    add)
      local name="${1:-}" path="${2:-$PWD}"
      [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { eqx_err "pakai: eqx bm add <nama> [path]  (nama: huruf/angka/_-.)"; return 1; }
      [[ -d "$path" ]] || { eqx_err "bukan direktori: $path"; return 1; }
      path="$(cd "$path" && pwd)"
      awk -F'\t' -v n="$name" '$1!=n' "$EQX_BM_FILE" >"$EQX_BM_FILE.tmp" 2>/dev/null; mv -f "$EQX_BM_FILE.tmp" "$EQX_BM_FILE"
      printf '%s\t%s\n' "$name" "$path" >>"$EQX_BM_FILE"
      eqx_ok "bookmark '$name' -> $path" ;;
    go|cd)
      local name="${1:-}" path
      path="$(awk -F'\t' -v n="$name" '$1==n{print $2}' "$EQX_BM_FILE" | head -n1)"
      [[ -n "$path" ]] || { eqx_err "bookmark tidak ditemukan: $name"; return 1; }
      if [[ $- == *i* ]]; then cd "$path" || return 1; eqx_ok "pindah ke $path"
      else printf '%s\n' "$path"; fi ;;
    del|rm)
      local name="${1:-}"
      awk -F'\t' -v n="$name" '$1!=n' "$EQX_BM_FILE" >"$EQX_BM_FILE.tmp" && mv -f "$EQX_BM_FILE.tmp" "$EQX_BM_FILE"
      eqx_ok "bookmark '$name' dihapus (jika ada)" ;;
    list|ls)
      if [[ -s "$EQX_BM_FILE" ]]; then
        while IFS=$'\t' read -r n p; do printf '  %s%-14s%s %s\n' "$C_A" "$n" "$C_R" "$p"; done <"$EQX_BM_FILE"
      else eqx_dim "  (belum ada bookmark)  -  tambah: eqx bm add proyek"; fi ;;
    *) eqx_err "subperintah: add | go | list | del"; return 1 ;;
  esac
}

eqx_cmd_rename() { # sed-expr berkas...
  local expr="${1:-}"; shift || true
  [[ -n "$expr" && $# -ge 1 ]] || { eqx_err "pakai: eqx rename 's/lama/baru/' <berkas...>"; return 1; }
  local f new n=0
  local -a plan=()
  for f in "$@"; do
    [[ -e "$f" ]] || continue
    new="$(printf '%s' "$(basename "$f")" | sed -e "$expr" 2>/dev/null)" || { eqx_err "ekspresi sed tidak valid"; return 1; }
    [[ -n "$new" && "$new" != "$(basename "$f")" ]] || continue
    plan+=("$f"$'\t'"$(dirname "$f")/$new")
  done
  (( ${#plan[@]} )) || { eqx_info "tidak ada yang berubah"; return 0; }
  for f in "${plan[@]}"; do printf '  %s  ->  %s\n' "${f%%$'\t'*}" "${f#*$'\t'}"; done
  eqx_confirm "Terapkan ${#plan[@]} perubahan nama?" n || { eqx_info "dibatalkan"; return 0; }
  for f in "${plan[@]}"; do
    if [[ -e "${f#*$'\t'}" ]]; then eqx_warn "lewati (sudah ada): ${f#*$'\t'}"; continue; fi
    mv -- "${f%%$'\t'*}" "${f#*$'\t'}" && n=$(( n + 1 ))
  done
  eqx_ok "$n berkas diganti namanya"
}

eqx_cmd_calc() { # ekspresi
  local expr="$*" chk fn out
  [[ -n "$expr" ]] || { eqx_err "pakai: eqx calc '2+2*3'   (mendukung sqrt, sin, cos, exp, log, int)"; return 1; }
  # Validasi: hanya angka, operator, kurung, dan nama fungsi matematika yang dikenal
  chk="$expr"
  for fn in sqrt sin cos atan2 exp log int; do chk="${chk//$fn/}"; done
  if [[ ! "$chk" =~ ^[-0-9+*/().%^[:space:],]*$ ]]; then
    eqx_err "ekspresi mengandung karakter yang tidak diizinkan"; return 1
  fi
  # Ekspresi tanpa fungsi (kecuali sqrt) dihitung dengan bc jika tersedia
  chk="${expr//sqrt/}"
  if eqx_have bc && [[ "$chk" =~ ^[-0-9+*/().^[:space:]]*$ ]]; then
    out="$(printf 'scale=10; %s\n' "$expr" | bc -l 2>/dev/null)"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out" | sed -E 's/(\.[0-9]*[1-9])0+$/\1/; s/\.0+$//'
      return 0
    fi
  fi
  out="$(awk "BEGIN{ printf \"%.10g\\n\", ($expr) }" 2>/dev/null)"
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else eqx_err "ekspresi tidak valid"; return 1; fi
}

# =============================================================================
# 12. PRODUKTIVITAS
# =============================================================================
eqx_cmd_note() { # add|list|show|del|search|edit|clear
  local sub="${1:-list}"; [[ $# -gt 0 ]] && shift
  mkdir -p "$(dirname "$EQX_NOTES_FILE")"; touch "$EQX_NOTES_FILE"
  case "$sub" in
    add|a)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx note add <teks catatan>"; return 1; }
      printf '%s\t%s\n' "$(date +%s)" "$*" >>"$EQX_NOTES_FILE"
      eqx_ok "catatan #$(wc -l <"$EQX_NOTES_FILE" | tr -d ' ') disimpan" ;;
    list|ls)
      [[ -s "$EQX_NOTES_FILE" ]] || { eqx_dim "  (belum ada catatan)  -  tambah: eqx note add \"teks\""; return 0; }
      local i=0 ts text
      while IFS=$'\t' read -r ts text; do
        i=$(( i + 1 ))
        printf '  %s%3d%s  %s%s%s  %s\n' "$C_A" "$i" "$C_R" "$C_D" "$(date -d "@$ts" '+%d/%m %H:%M' 2>/dev/null)" "$C_R" "$text"
      done <"$EQX_NOTES_FILE" ;;
    show)
      local n="${1:-}" line
      [[ "$n" =~ ^[0-9]+$ ]] || { eqx_err "pakai: eqx note show <nomor>"; return 1; }
      line="$(sed -n "${n}p" "$EQX_NOTES_FILE")"
      [[ -n "$line" ]] || { eqx_err "catatan #$n tidak ada"; return 1; }
      printf '%s\n' "${line#*$'\t'}" ;;
    del|rm)
      local n="${1:-}"
      [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= $(wc -l <"$EQX_NOTES_FILE") )) || { eqx_err "nomor catatan tidak valid"; return 1; }
      sed -i "${n}d" "$EQX_NOTES_FILE" && eqx_ok "catatan #$n dihapus" ;;
    search|find)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx note search <kata>"; return 1; }
      awk -F'\t' -v q="${*,,}" 'index(tolower($2), q) {printf "  %3d  %s\n", NR, $2; n++} END{if(!n) print "  (tidak ada hasil)"}' "$EQX_NOTES_FILE" ;;
    edit)
      local ed; ed="$(eqx_editor)"
      [[ -n "$ed" ]] || { eqx_err "tidak ada editor. Pasang: eqx pkg install nano"; return 1; }
      "$ed" "$EQX_NOTES_FILE" ;;
    clear)
      eqx_confirm "Hapus SEMUA catatan?" n && : >"$EQX_NOTES_FILE" && eqx_ok "semua catatan dihapus" ;;
    *) # jika subperintah bukan kata kunci, anggap sebagai catatan baru
      eqx_cmd_note add "$sub" "$@" ;;
  esac
}

eqx_cmd_todo() { # add|list|done|undo|del|clear
  local sub="${1:-list}"; [[ $# -gt 0 ]] && shift
  mkdir -p "$(dirname "$EQX_TODO_FILE")"; touch "$EQX_TODO_FILE"
  local -a lines=()
  mapfile -t lines <"$EQX_TODO_FILE"
  case "$sub" in
    add|a)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx todo add <tugas> [!tinggi|!rendah]"; return 1; }
      local prio="2" text="$*"
      if [[ "$text" == *"!tinggi"* ]]; then prio="1"; text="${text//!tinggi/}"
      elif [[ "$text" == *"!rendah"* ]]; then prio="3"; text="${text//!rendah/}"; fi
      text="${text%"${text##*[![:space:]]}"}"
      printf '0\t%s\t%s\t%s\n' "$prio" "$(date +%s)" "$text" >>"$EQX_TODO_FILE"
      eqx_ok "tugas ditambahkan: $text" ;;
    list|ls)
      (( ${#lines[@]} )) || { eqx_dim "  (daftar tugas kosong)  -  tambah: eqx todo add \"beli pulsa\""; return 0; }
      local i st pr ts tx mark pc done_n=0
      for i in "${!lines[@]}"; do
        IFS=$'\t' read -r st pr ts tx <<<"${lines[i]}"
        case "$pr" in 1) pc="$C_E";; 3) pc="$C_D";; *) pc="$C_W";; esac
        if [[ "$st" == 1 ]]; then mark="${C_OK}[${S_OK}]${C_R}"; done_n=$(( done_n + 1 )); tx="${C_D}${tx}${C_R}"
        else mark="${pc}[ ]${C_R}"; fi
        printf '  %s%3d%s %s %s\n' "$C_A" "$(( i + 1 ))" "$C_R" "$mark" "$tx"
      done
      printf '\n  %s%d/%d selesai%s\n' "$C_D" "$done_n" "${#lines[@]}" "$C_R" ;;
    done|undo)
      local n="${1:-}" want=1; [[ "$sub" == undo ]] && want=0
      [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#lines[@]} )) || { eqx_err "nomor tugas tidak valid"; return 1; }
      local st pr ts tx
      IFS=$'\t' read -r st pr ts tx <<<"${lines[n-1]}"
      lines[n-1]="$want"$'\t'"$pr"$'\t'"$ts"$'\t'"$tx"
      printf '%s\n' "${lines[@]}" >"$EQX_TODO_FILE"
      eqx_ok "tugas #$n ditandai $( (( want )) && echo selesai || echo 'belum selesai' )" ;;
    del|rm)
      local n="${1:-}"
      [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#lines[@]} )) || { eqx_err "nomor tugas tidak valid"; return 1; }
      unset 'lines[n-1]'
      if (( ${#lines[@]} )); then printf '%s\n' "${lines[@]}" >"$EQX_TODO_FILE"; else : >"$EQX_TODO_FILE"; fi
      eqx_ok "tugas #$n dihapus" ;;
    clear)
      local l keep=()
      for l in "${lines[@]}"; do [[ "${l:0:1}" == 1 ]] || keep+=("$l"); done
      if (( ${#keep[@]} )); then printf '%s\n' "${keep[@]}" >"$EQX_TODO_FILE"; else : >"$EQX_TODO_FILE"; fi
      eqx_ok "tugas selesai dibersihkan" ;;
    *) eqx_cmd_todo add "$sub" "$@" ;;
  esac
}

eqx_cmd_timer() { # durasi [pesan]
  local spec="${1:-}" msg="${2:-Waktu habis!}" secs end left key="" cancelled=0 total
  [[ -n "$spec" ]] || { eqx_err "pakai: eqx timer <durasi> [pesan]   contoh: 90, 5m, 1h30m"; return 1; }
  secs="$(eqx_parse_duration "$spec")" || { eqx_err "durasi tidak valid: $spec"; return 1; }
  (( secs > 0 )) || { eqx_err "durasi harus lebih dari 0"; return 1; }
  total=$secs; end=$(( $(date +%s) + secs ))
  eqx_screen_enter
  while (( ! EQX_STOP )); do
    left=$(( end - $(date +%s) )); (( left < 0 )) && left=0
    printf '\033[H\n'
    eqx_bigtext "$(eqx_hms "$left")"
    eqx_line ""
    eqx_line "  $(eqx_bar $(( (total - left) * 100 / total )) 30)"
    eqx_line "  ${C_D}${msg}  -  q untuk batal${C_R}"
    (( left == 0 )) && break
    if read -rsn1 -t 0.4 key; then [[ "$key" == q || "$key" == Q ]] && { cancelled=1; break; }; fi
  done
  (( EQX_STOP )) && cancelled=1
  eqx_screen_leave
  if (( cancelled )); then eqx_info "timer dibatalkan"; else eqx_alert "$msg"; fi
}

eqx_cmd_stopwatch() {
  local start now key="" laps=() el prev=0
  start=$(date +%s.%N 2>/dev/null || date +%s)
  eqx_screen_enter
  while (( ! EQX_STOP )); do
    now=$(date +%s.%N 2>/dev/null || date +%s)
    el="$(awk -v a="$now" -v b="$start" 'BEGIN{printf "%.1f", a-b}')"
    printf '\033[H\n'
    local secs="${el%.*}" tenth="${el#*.}"
    eqx_bigtext "$(eqx_hms "$secs").$tenth"
    eqx_line ""
    eqx_line "  ${C_D}l = putaran   q = berhenti${C_R}"
    local i
    for i in "${!laps[@]}"; do eqx_line "  ${C_A}Putaran $(( i + 1 ))${C_R}  ${laps[i]}"; done
    printf '\033[J'
    if read -rsn1 -t 0.1 key; then
      case "$key" in
        q|Q) break ;;
        l|L) laps+=("$el s") ;;
      esac
    fi
  done
  eqx_screen_leave
  eqx_ok "Waktu akhir: ${el:-0} detik"
}

eqx_cmd_pomodoro() { # [kerja-menit] [istirahat-menit] [siklus]
  local w="${1:-25}" b="${2:-5}" n="${3:-4}" i
  [[ "$w" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$n" =~ ^[0-9]+$ ]] || { eqx_err "pakai: eqx pomodoro [kerja=25] [istirahat=5] [siklus=4]"; return 1; }
  for (( i = 1; i <= n; i++ )); do
    eqx_step "Siklus $i/$n: fokus ${w} menit"
    eqx_cmd_timer "${w}m" "Fokus selesai. Saatnya istirahat!" || return 1
    (( i == n )) && break
    eqx_step "Istirahat ${b} menit"
    eqx_cmd_timer "${b}m" "Istirahat selesai. Ayo lanjut!" || return 1
  done
  eqx_ok "Semua siklus pomodoro selesai. Kerja bagus!"
}

eqx_cmd_hist() { # top|search|clear|stats
  local sub="${1:-top}"; [[ $# -gt 0 ]] && shift
  local f="$EQX_HISTFILE"
  [[ -f "$f" ]] || { eqx_warn "belum ada riwayat di $f"; return 1; }
  case "$sub" in
    top)
      local n="${1:-10}"; [[ "$n" =~ ^[0-9]+$ ]] || n=10
      awk '{print $1}' "$f" | sort | uniq -c | sort -rn | head -n "$n" | awk '{printf "  %6d  %s\n", $1, $2}' ;;
    search)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx hist search <kata>"; return 1; }
      grep -n -i --color=auto -- "$*" "$f" | tail -n 40 ;;
    stats)
      eqx_kv "Total entri" "$(wc -l <"$f" | tr -d ' ')" 14
      eqx_kv "Perintah unik" "$(sort -u "$f" | wc -l | tr -d ' ')" 14
      eqx_kv "File" "$f" 14 ;;
    clear)
      eqx_confirm "Hapus seluruh riwayat?" n && : >"$f" && history -c 2>/dev/null && eqx_ok "riwayat dihapus" ;;
    *) eqx_err "subperintah: top | search | stats | clear"; return 1 ;;
  esac
}

# =============================================================================
# 13. KEAMANAN & UTILITAS DATA
# =============================================================================
eqx_cmd_pass() { # [panjang] [jumlah] [--simple|--pin]
  local len=20 count=1 mode=full a charset p i
  for a in "$@"; do
    case "$a" in
      --simple) mode=simple ;;
      --pin) mode=pin ;;
      ''|*[!0-9]*) eqx_err "argumen tidak dikenal: $a"; return 1 ;;
      *) if (( len == 20 && count == 1 )) && [[ -z "${_len_set:-}" ]]; then len="$a"; _len_set=1; else count="$a"; fi ;;
    esac
  done
  unset _len_set
  (( len >= 4 && len <= 128 )) || { eqx_err "panjang harus 4-128"; return 1; }
  (( count >= 1 && count <= 20 )) || { eqx_err "jumlah harus 1-20"; return 1; }
  case "$mode" in
    pin)    charset='0-9' ;;
    simple) charset='A-Za-z0-9' ;;
    *)      charset='A-Za-z0-9!@#%^&*()_+=<>?-' ;;
  esac
  for (( i = 0; i < count; i++ )); do
    while :; do
      p="$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | head -c "$len")"
      [[ ${#p} -eq $len ]] || continue
      [[ "$mode" == full ]] || break
      [[ "$p" =~ [a-z] && "$p" =~ [A-Z] && "$p" =~ [0-9] && "$p" =~ [^A-Za-z0-9] ]] && break
    done
    printf '  %s%s%s\n' "$C_OK" "$p" "$C_R"
  done
  local pool=94; [[ $mode == simple ]] && pool=62; [[ $mode == pin ]] && pool=10
  awk -v l="$len" -v p="$pool" 'BEGIN{printf "  perkiraan entropi: %.0f bit\n", l*log(p)/log(2)}' | sed "s/^/${C_D}/; s/\$/${C_R}/"
}

eqx_cmd_hash() { # [-a algoritma] <file> | -s <teks>
  local algo="sha256" mode=file
  while [[ "${1:-}" == -* ]]; do
    case "$1" in
      -a) algo="${2:-sha256}"; shift 2 ;;
      -s) mode=str; shift ;;
      *) eqx_err "opsi tidak dikenal: $1"; return 1 ;;
    esac
  done
  [[ "$algo" =~ ^(md5|sha1|sha256|sha512)$ ]] || { eqx_err "algoritma: md5 | sha1 | sha256 | sha512"; return 1; }
  local cmd="${algo}sum"
  eqx_need "$cmd" coreutils || return 1
  if [[ "$mode" == str ]]; then
    [[ $# -ge 1 ]] || { eqx_err "pakai: eqx hash -s <teks>"; return 1; }
    printf '%s' "$*" | "$cmd" | awk '{print $1}'
  else
    [[ $# -ge 1 ]] || { eqx_err "pakai: eqx hash [-a algo] <file...>"; return 1; }
    "$cmd" -- "$@"
  fi
}

eqx_cmd_verify() { # file hash
  local f="${1:-}" h="${2:-}" algo calc
  [[ -f "$f" && -n "$h" ]] || { eqx_err "pakai: eqx verify <file> <hash>"; return 1; }
  case ${#h} in 32) algo=md5;; 40) algo=sha1;; 64) algo=sha256;; 128) algo=sha512;; *) eqx_err "panjang hash tidak dikenal"; return 1;; esac
  calc="$("${algo}sum" -- "$f" | awk '{print $1}')"
  if [[ "${calc,,}" == "${h,,}" ]]; then eqx_ok "COCOK ($algo)"; else eqx_err "TIDAK COCOK ($algo)"; eqx_dim "  hitung: $calc"; return 1; fi
}

eqx_cmd_b64() { # enc|dec <teks>
  local sub="${1:-}"; [[ $# -gt 0 ]] && shift
  eqx_need base64 coreutils || return 1
  case "$sub" in
    enc|e) if [[ $# -gt 0 ]]; then printf '%s' "$*" | base64 | tr -d '\n'; echo; else base64 | tr -d '\n'; echo; fi ;;
    dec|d) if [[ $# -gt 0 ]]; then printf '%s' "$*" | base64 -d 2>/dev/null; echo; else base64 -d; echo; fi ;;
    *) eqx_err "pakai: eqx b64 enc|dec <teks>   (atau lewat pipe)"; return 1 ;;
  esac
}

eqx_cmd_url() { # enc|dec <teks>
  local sub="${1:-}"; [[ $# -gt 0 ]] && shift
  local s="$*" i c out=""
  case "$sub" in
    enc|e)
      for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in [A-Za-z0-9.~_-]) out+="$c" ;; *) out+="$(printf '%s' "$c" | od -An -tx1 | tr -d '\n' | tr 'a-f' 'A-F' | sed 's/ /%/g; s/%$//')" ;; esac
      done
      printf '%s\n' "$out" ;;
    dec|d)
      s="${s//+/ }"
      printf '%b\n' "${s//%/\\x}" ;;
    *) eqx_err "pakai: eqx url enc|dec <teks>"; return 1 ;;
  esac
}

eqx_cmd_uuid() {
  local n="${1:-1}" i u
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 50 )) || n=1
  for (( i = 0; i < n; i++ )); do
    if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    elif eqx_have uuidgen; then uuidgen
    else
      u="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 32)"
      printf '%s-%s-4%s-a%s-%s\n' "${u:0:8}" "${u:8:4}" "${u:13:3}" "${u:17:3}" "${u:20:12}"
    fi
  done
}

eqx_cmd_rand() { # [min] [max]
  local lo="${1:-1}" hi="${2:-100}"
  [[ "$lo" =~ ^-?[0-9]+$ && "$hi" =~ ^-?[0-9]+$ ]] && (( lo <= hi )) || { eqx_err "pakai: eqx rand [min] [max]"; return 1; }
  local span=$(( hi - lo + 1 )) r
  r=$(( (RANDOM * 32768 + RANDOM) % span + lo ))
  printf '%s\n' "$r"
}

eqx_cmd_crypt() { # enc|dec <file>
  local sub="${1:-}" f="${2:-}"
  eqx_need openssl openssl-tool || return 1
  [[ -f "$f" ]] || { eqx_err "pakai: eqx crypt enc|dec <file>"; return 1; }
  case "$sub" in
    enc) openssl enc -aes-256-cbc -pbkdf2 -salt -in "$f" -out "$f.enc" && eqx_ok "Terenkripsi: $f.enc (simpan password-nya!)" ;;
    dec)
      [[ "$f" == *.enc ]] || { eqx_err "file harus berekstensi .enc"; return 1; }
      [[ -e "${f%.enc}" ]] && { eqx_err "${f%.enc} sudah ada, pindahkan dulu"; return 1; }
      openssl enc -d -aes-256-cbc -pbkdf2 -in "$f" -out "${f%.enc}" && eqx_ok "Didekripsi: ${f%.enc}" ;;
    *) eqx_err "pakai: eqx crypt enc|dec <file>"; return 1 ;;
  esac
}

# =============================================================================
# 14. PAKET
# =============================================================================
eqx__pkg_run() { # aksi paket...
  local act="$1"; shift
  case "$EQX_PKGMGR" in
    pkg)    case "$act" in
              install) pkg install -y "$@" ;;  remove) pkg uninstall -y "$@" ;;
              search) pkg search "$@" ;;       update) pkg update -y ;;
              upgrade) pkg update -y && pkg upgrade -y ;;
              list) pkg list-installed ;;      info) apt show "$1" ;;
              clean) apt clean && apt autoclean ;;
            esac ;;
    apt)    case "$act" in
              install) $EQX_SUDO apt-get install -y "$@" ;; remove) $EQX_SUDO apt-get remove -y "$@" ;;
              search) apt-cache search "$@" ;;              update) $EQX_SUDO apt-get update ;;
              upgrade) $EQX_SUDO apt-get update && $EQX_SUDO apt-get upgrade -y ;;
              list) dpkg -l ;;  info) apt-cache show "$1" ;;  clean) $EQX_SUDO apt-get clean ;;
            esac ;;
    dnf)    case "$act" in
              install) $EQX_SUDO dnf install -y "$@" ;; remove) $EQX_SUDO dnf remove -y "$@" ;;
              search) dnf search "$@" ;;  update|upgrade) $EQX_SUDO dnf upgrade -y ;;
              list) dnf list installed ;; info) dnf info "$1" ;; clean) $EQX_SUDO dnf clean all ;;
            esac ;;
    pacman) case "$act" in
              install) $EQX_SUDO pacman -S --noconfirm "$@" ;; remove) $EQX_SUDO pacman -Rns --noconfirm "$@" ;;
              search) pacman -Ss "$@" ;;  update|upgrade) $EQX_SUDO pacman -Syu --noconfirm ;;
              list) pacman -Q ;; info) pacman -Si "$1" ;; clean) $EQX_SUDO pacman -Sc --noconfirm ;;
            esac ;;
    apk)    case "$act" in
              install) $EQX_SUDO apk add "$@" ;; remove) $EQX_SUDO apk del "$@" ;;
              search) apk search "$@" ;;  update) $EQX_SUDO apk update ;; upgrade) $EQX_SUDO apk upgrade ;;
              list) apk info ;; info) apk info "$1" ;; clean) $EQX_SUDO apk cache clean ;;
            esac ;;
    zypper) case "$act" in
              install) $EQX_SUDO zypper install -y "$@" ;; remove) $EQX_SUDO zypper remove -y "$@" ;;
              search) zypper search "$@" ;;  update|upgrade) $EQX_SUDO zypper update -y ;;
              list) zypper search -i ;; info) zypper info "$1" ;; clean) $EQX_SUDO zypper clean ;;
            esac ;;
    *) eqx_err "tidak ada package manager yang dikenali"; return 1 ;;
  esac
}

eqx_cmd_pkg() { # install|remove|search|update|upgrade|list|info|clean|count
  local sub="${1:-}"; [[ $# -gt 0 ]] && shift
  case "$sub" in
    install|i|add)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx pkg install <paket...>"; return 1; }
      eqx__pkg_run install "$@" ;;
    remove|rm|uninstall)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx pkg remove <paket...>"; return 1; }
      eqx__pkg_run remove "$@" ;;
    search|s)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx pkg search <kata>"; return 1; }
      eqx__pkg_run search "$@" ;;
    update|upgrade|up) eqx__pkg_run upgrade ;;
    list|ls) eqx__pkg_run list ;;
    info)
      [[ $# -ge 1 ]] || { eqx_err "pakai: eqx pkg info <paket>"; return 1; }
      eqx__pkg_run info "$1" ;;
    clean) eqx__pkg_run clean ;;
    count) eqx_kv "Paket terpasang" "$(eqx_pkg_count)" 18 ;;
    "") eqx_err "subperintah: install | remove | search | upgrade | list | info | clean | count"; return 1 ;;
    *) eqx_err "subperintah tidak dikenal: $sub"; return 1 ;;
  esac
}

declare -gA EQX_BUNDLES=(
  [base]="git curl wget nano vim openssh zip unzip tar"
  [dev]="python nodejs clang make cmake git"
  [net]="nmap netcat-openbsd dnsutils traceroute whois net-tools inetutils"
  [term]="tmux htop ncdu tree fzf ripgrep fd bat jq"
  [fun]="figlet cowsay toilet"
  [media]="ffmpeg imagemagick"
  [api]="termux-api"
)

eqx_cmd_tools() { # [list|install <bundle>|all]
  local sub="${1:-list}" b p
  case "$sub" in
    list)
      eqx_title "Bundle Alat"
      for b in base dev net term fun media api; do
        printf '\n  %s%s%s\n    %s\n' "$C_A" "$b" "$C_R" "${EQX_BUNDLES[$b]}"
      done
      printf '\n'; eqx_dim "  Pasang: eqx tools install <bundle>   (contoh: eqx tools install dev)" ;;
    install)
      b="${2:-}"
      [[ -n "${EQX_BUNDLES[$b]:-}" ]] || { eqx_err "bundle tidak dikenal. Lihat: eqx tools list"; return 1; }
      # shellcheck disable=SC2086
      eqx__pkg_run install ${EQX_BUNDLES[$b]} ;;
    status)
      for p in git curl wget nano vim python node clang tmux htop jq nmap ffmpeg figlet termux-battery-status; do
        if eqx_have "$p"; then printf '  %s%s%s %s\n' "$C_OK" "$S_OK" "$C_R" "$p"
        else printf '  %s%s%s %s\n' "$C_D" "$S_EMPTY" "$C_R" "$p"; fi
      done ;;
    *) eqx_err "subperintah: list | install <bundle> | status"; return 1 ;;
  esac
}

eqx_cmd_git() { # [status|log|user]
  eqx_need git git || return 1
  local sub="${1:-status}"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    if [[ "$sub" != user ]]; then eqx_warn "bukan repositori git: $PWD"; return 1; fi
  }
  case "$sub" in
    status)
      eqx_kv "Cabang" "$(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')" 10
      eqx_kv "Remote" "$(git remote -v 2>/dev/null | head -n1 | awk '{print $2}')" 10
      eqx_section "Perubahan"; git status -sb
      eqx_section "5 commit terakhir"; git log --oneline -n 5 --decorate ;;
    log) git log --graph --oneline --decorate -n "${2:-15}" ;;
    user)
      local n m
      eqx_ask "Nama git" n "$(git config --global user.name 2>/dev/null)"
      eqx_ask "Email git" m "$(git config --global user.email 2>/dev/null)"
      [[ -n "$n" && -n "$m" ]] || { eqx_err "nama dan email wajib diisi"; return 1; }
      git config --global user.name "$n" && git config --global user.email "$m" && eqx_ok "identitas git disimpan" ;;
    *) eqx_err "subperintah: status | log [n] | user"; return 1 ;;
  esac
}

# =============================================================================
# 15. TERMUX
# =============================================================================
eqx_cmd_termux() { # storage|reload|keys|api|notify|vibrate|clip|toast|torch
  local sub="${1:-api}"; [[ $# -gt 0 ]] && shift
  if (( ! EQX_IS_TERMUX )); then eqx_warn "bukan lingkungan Termux; beberapa perintah tidak berlaku."; fi
  case "$sub" in
    storage)
      eqx_have termux-setup-storage || { eqx_err "termux-setup-storage tidak ada"; return 1; }
      termux-setup-storage && eqx_ok "izin penyimpanan diminta. Cek folder ~/storage setelah mengizinkan." ;;
    reload)
      eqx_have termux-reload-settings && termux-reload-settings && eqx_ok "pengaturan Termux dimuat ulang" ;;
    keys)
      local prop="$HOME/.termux/termux.properties" preset="${1:-default}" keys
      case "$preset" in
        default) keys="[['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]" ;;
        dev)     keys="[['ESC','|','/','~','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','{','LEFT','DOWN','RIGHT','PGDN']]" ;;
        mini)    keys="[['ESC','TAB','CTRL','ALT','LEFT','DOWN','UP','RIGHT']]" ;;
        *) eqx_err "preset: default | dev | mini"; return 1 ;;
      esac
      mkdir -p "$HOME/.termux"
      if [[ -f "$prop" ]]; then
        cp -a "$prop" "$prop.bak.$(date +%Y%m%d-%H%M%S)"
        grep -v '^[[:space:]]*extra-keys[[:space:]]*=' "$prop" >"$prop.tmp"; mv -f "$prop.tmp" "$prop"
      fi
      printf 'extra-keys = %s\n' "$keys" >>"$prop"
      eqx_ok "extra-keys '$preset' ditulis ke $prop (backup dibuat). Jalankan: eqx termux reload" ;;
    api)
      eqx_title "Termux:API"
      if eqx_have termux-battery-status; then
        eqx_ok "paket termux-api terpasang"
        if timeout 4 termux-battery-status >/dev/null 2>&1; then eqx_ok "aplikasi Termux:API merespons"
        else eqx_warn "aplikasi Termux:API belum terpasang / tidak merespons (pasang dari F-Droid)"; fi
      else eqx_warn "belum terpasang. Jalankan: eqx pkg install termux-api"; fi ;;
    notify)
      eqx_need termux-notification termux-api || return 1
      termux-notification --title "${1:-Equinox}" --content "${2:-Halo dari Equinox}" && eqx_ok "notifikasi terkirim" ;;
    vibrate) eqx_need termux-vibrate termux-api || return 1; termux-vibrate -d "${1:-300}" ;;
    toast)   eqx_need termux-toast termux-api || return 1; termux-toast "${*:-Equinox}" ;;
    torch)   eqx_need termux-torch termux-api || return 1; termux-torch "${1:-on}" ;;
    clip)
      eqx_need termux-clipboard-get termux-api || return 1
      if [[ "${1:-get}" == set ]]; then shift; termux-clipboard-set "$*" && eqx_ok "disalin ke clipboard"
      else termux-clipboard-get; echo; fi ;;
    *) eqx_err "subperintah: storage | reload | keys [preset] | api | notify | vibrate | toast | torch | clip"; return 1 ;;
  esac
}

# =============================================================================
# 16. KUSTOMISASI
# =============================================================================
eqx_cmd_theme() { # list|set|preview|current
  local sub="${1:-list}" t i
  case "$sub" in
    list|ls)
      eqx_title "Tema"
      for t in "${EQX_THEME_ORDER[@]}"; do
        local -a n; read -r -a n <<<"${EQX_THEMES[$t]}"
        printf '  %-9s ' "$t"
        for i in "${n[@]}"; do (( EQX_COLOR )) && printf '\e[48;5;%sm  \e[0m' "$i" || printf '[]'; done
        [[ "$t" == "$EQX_THEME_NAME" ]] && printf '  %s<- aktif%s' "$C_OK" "$C_R"
        printf '\n'
      done ;;
    set)
      t="${2:-}"
      [[ -n "${EQX_THEMES[$t]:-}" ]] || { eqx_err "tema tidak dikenal. pilihan: ${EQX_THEME_ORDER[*]}"; return 1; }
      eqx_cfg_set THEME "$t" || return 1
      eqx_theme_apply "$t"
      [[ $- == *i* ]] && eqx_build_prompt 0
      eqx_ok "tema diganti ke $t" ;;
    preview)
      t="${2:-$EQX_THEME_NAME}"
      [[ -n "${EQX_THEMES[$t]:-}" ]] || { eqx_err "tema tidak dikenal"; return 1; }
      local old="$EQX_THEME_NAME"; eqx_theme_apply "$t"
      eqx_logo; eqx_ok "contoh sukses"; eqx_warn "contoh peringatan"; eqx_err "contoh galat"; eqx_info "contoh info"
      printf '  '; eqx_bar 35 20; printf '  '; eqx_bar 70 20; printf '  '; eqx_bar 95 20; printf '\n'
      eqx_theme_apply "$old" ;;
    current) printf '%s\n' "$EQX_THEME_NAME" ;;
    *) eqx_err "subperintah: list | set <nama> | preview [nama] | current"; return 1 ;;
  esac
}

eqx_cmd_prompt() { # list|set|preview
  local sub="${1:-list}" s
  case "$sub" in
    list|ls)
      for s in "${EQX_PROMPT_STYLES[@]}"; do
        printf '  %s%-9s%s' "$C_A" "$s" "$C_R"
        [[ "$s" == "${EQX_CFG[PROMPT_STYLE]}" ]] && printf ' %s<- aktif%s' "$C_OK" "$C_R"
        printf '\n'
      done ;;
    set)
      s="${2:-}"
      eqx_cfg_set PROMPT_STYLE "$s" || return 1
      [[ $- == *i* ]] && eqx_build_prompt 0
      eqx_ok "gaya prompt: $s" ;;
    user)
      eqx_cfg_set PROMPT_USER "${2:-}" || return 1
      [[ $- == *i* ]] && eqx_build_prompt 0
      eqx_ok "nama di prompt diperbarui" ;;
    *) eqx_err "subperintah: list | set <gaya> | user <nama>"; return 1 ;;
  esac
}

eqx_cmd_alias() { # list|add|del
  local sub="${1:-list}"; [[ $# -gt 0 ]] && shift
  touch "$EQX_ALIAS_FILE"
  case "$sub" in
    list|ls)
      if [[ -s "$EQX_ALIAS_FILE" ]]; then sed -e 's/^alias //' -e 's/^/  /' "$EQX_ALIAS_FILE"
      else eqx_dim "  (belum ada alias kustom)  -  tambah: eqx alias add gs 'git status'"; fi ;;
    add)
      local name="${1:-}"; shift || true
      local cmd="$*"
      [[ "$name" =~ ^[A-Za-z0-9_.-]+$ && -n "$cmd" ]] || { eqx_err "pakai: eqx alias add <nama> <perintah>"; return 1; }
      [[ "$cmd" == *"'"* ]] && { eqx_err "perintah tidak boleh memuat tanda kutip tunggal (')"; return 1; }
      grep -v "^alias ${name}=" "$EQX_ALIAS_FILE" >"$EQX_ALIAS_FILE.tmp" 2>/dev/null; mv -f "$EQX_ALIAS_FILE.tmp" "$EQX_ALIAS_FILE"
      printf "alias %s='%s'\n" "$name" "$cmd" >>"$EQX_ALIAS_FILE"
      alias "$name=$cmd" 2>/dev/null
      eqx_ok "alias '$name' disimpan" ;;
    del|rm)
      local name="${1:-}"
      grep -v "^alias ${name}=" "$EQX_ALIAS_FILE" >"$EQX_ALIAS_FILE.tmp" 2>/dev/null; mv -f "$EQX_ALIAS_FILE.tmp" "$EQX_ALIAS_FILE"
      unalias "$name" 2>/dev/null
      eqx_ok "alias '$name' dihapus (jika ada)" ;;
    *) eqx_err "subperintah: list | add <nama> <perintah> | del <nama>"; return 1 ;;
  esac
}

eqx_cmd_config() { # list|get|set|reset|edit|path
  local sub="${1:-list}" k
  case "$sub" in
    list|ls)
      eqx_title "Konfigurasi"
      for k in "${EQX_CFG_ORDER[@]}"; do eqx_kv "$k" "${EQX_CFG[$k]:-}" 18; done ;;
    get)
      k="${2^^}"; [[ -n "${EQX_CFG_DEF[$k]+x}" ]] || { eqx_err "kunci tidak dikenal"; return 1; }
      printf '%s\n' "${EQX_CFG[$k]}" ;;
    set)
      [[ $# -ge 3 ]] || { eqx_err "pakai: eqx config set <KUNCI> <nilai>"; return 1; }
      eqx_cfg_set "$2" "${*:3}" && eqx_ok "${2^^} = ${*:3}   (jalankan 'eqx reload' agar berlaku penuh)" ;;
    reset)
      eqx_confirm "Kembalikan semua pengaturan ke default?" n || return 0
      rm -f "$EQX_CONF"; eqx_cfg_load; eqx_cfg_save; eqx_ok "konfigurasi direset" ;;
    edit)
      local ed; ed="$(eqx_editor)"
      [[ -n "$ed" ]] || { eqx_err "tidak ada editor. Pasang: eqx pkg install nano"; return 1; }
      "$ed" "$EQX_CONF" ;;
    path) printf '%s\n' "$EQX_CONF" ;;
    *) eqx_err "subperintah: list | get <K> | set <K> <V> | reset | edit | path"; return 1 ;;
  esac
}

eqx_cmd_plugin() { # list|enable|disable|new|dir
  local sub="${1:-list}" name f
  mkdir -p "$EQX_PLUGIN_DIR"
  case "$sub" in
    list|ls)
      local any=0
      for f in "$EQX_PLUGIN_DIR"/*.sh "$EQX_PLUGIN_DIR"/*.sh.off; do
        [[ -e "$f" ]] || continue; any=1
        if [[ "$f" == *.off ]]; then printf '  %s%s%s %s %s(nonaktif)%s\n' "$C_D" "$S_EMPTY" "$C_R" "$(basename "${f%.off}")" "$C_D" "$C_R"
        else printf '  %s%s%s %s\n' "$C_OK" "$S_OK" "$C_R" "$(basename "$f")"; fi
      done
      (( any )) || eqx_dim "  (belum ada plugin)  -  buat: eqx plugin new halo" ;;
    enable)
      name="${2:-}"; [[ -f "$EQX_PLUGIN_DIR/$name.sh.off" ]] || { eqx_err "plugin nonaktif '$name' tidak ada"; return 1; }
      mv "$EQX_PLUGIN_DIR/$name.sh.off" "$EQX_PLUGIN_DIR/$name.sh" && eqx_ok "plugin '$name' diaktifkan (jalankan eqx reload)" ;;
    disable)
      name="${2:-}"; [[ -f "$EQX_PLUGIN_DIR/$name.sh" ]] || { eqx_err "plugin '$name' tidak ada"; return 1; }
      mv "$EQX_PLUGIN_DIR/$name.sh" "$EQX_PLUGIN_DIR/$name.sh.off" && eqx_ok "plugin '$name' dinonaktifkan" ;;
    new)
      name="${2:-}"
      [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || { eqx_err "nama plugin: huruf kecil, angka, underscore (awali huruf)"; return 1; }
      f="$EQX_PLUGIN_DIR/$name.sh"
      [[ -e "$f" ]] && { eqx_err "plugin sudah ada: $f"; return 1; }
      cat >"$f" <<EOF
#!/usr/bin/env bash
# Plugin Equinox: $name
# Perintah plugin = fungsi bernama eqx_cmd_<nama>. Daftarkan agar muncul di 'eqx help'.

eqx_cmd_${name}() {
  eqx_ok "Halo dari plugin ${name}! Argumen: \$*"
}

eqx_reg ${name} plugin "Plugin buatan sendiri: ${name}" "eqx ${name} [argumen]"
EOF
      eqx_ok "template dibuat: $f"
      eqx_dim "  Edit lalu jalankan: eqx reload  ->  eqx $name" ;;
    dir) printf '%s\n' "$EQX_PLUGIN_DIR" ;;
    *) eqx_err "subperintah: list | enable <n> | disable <n> | new <n> | dir"; return 1 ;;
  esac
}

eqx_plugins_load() {
  local f
  for f in "$EQX_PLUGIN_DIR"/*.sh; do
    [[ -f "$f" ]] || continue
    # shellcheck source=/dev/null
    if ! source "$f" 2>/dev/null; then eqx_warn "plugin gagal dimuat: $(basename "$f")"; eqx_log WARN "plugin gagal: $f"; fi
  done
  return 0
}

eqx_cmd_banner() { # [teks]
  if [[ $# -gt 0 ]]; then
    if eqx_have figlet; then figlet -- "$*"; else eqx_bigtext_text "$*"; fi
  else
    eqx_banner force
  fi
}

# Teks besar sederhana (fallback tanpa figlet): hanya digit & ':' didukung font internal
eqx_bigtext_text() {
  local t="$*" ok=1 i
  for (( i = 0; i < ${#t}; i++ )); do [[ -n "${EQX_DIGITS[${t:i:1}]:-}" ]] || ok=0; done
  if (( ok )); then eqx_bigtext "$t"; else printf '%s%s%s\n' "$C_B$C_P" "$t" "$C_R"; eqx_dim "  (pasang figlet untuk teks besar: eqx pkg install figlet)"; fi
}

declare -ga EQX_TIPS=(
  "Ketik 'eqx menu' untuk membuka menu interaktif."
  "Ganti tampilan: 'eqx theme set matrix' atau 'eqx prompt set hacker'."
  "Catat cepat: 'eqx note add \"ide proyek\"'. Lihat dengan 'eqx note'."
  "'eqx doctor' memeriksa semua dependensi Equinox."
  "'eqx monitor' menampilkan RAM, disk, baterai, dan proses secara live."
  "Hindari rm yang tak bisa dibatalkan: pakai 'eqx trash put berkas'."
  "'eqx bm add proyek' lalu 'eqx bm go proyek' untuk lompat antar folder."
  "Buat password kuat: 'eqx pass 24' atau 'eqx pass 12 --simple'."
  "'eqx backup' membuat arsip .tar.gz dari HOME ke ~/.equinox/backups."
  "Tab-completion tersedia: ketik 'eqx th' lalu tekan Tab."
  "'eqx tools list' menampilkan bundle paket siap pasang (dev, net, term...)."
  "'eqx update' memperbarui Equinox dari GitHub."
  "'eqx big ~ 20' menampilkan 20 file terbesar di HOME."
  "'eqx pomodoro' membantu fokus dengan siklus kerja 25 menit."
  "Tulis plugin sendiri: 'eqx plugin new halo'."
)

eqx_cmd_tips() {
  printf '%s%s%s %s\n' "$C_W" "$S_INFO" "$C_R" "${EQX_TIPS[RANDOM % ${#EQX_TIPS[@]}]}"
}

eqx_banner() { # [force]
  [[ "${1:-}" == force || "${EQX_CFG[BANNER]}" == on ]] || return 0
  eqx_logo
  printf '  %sv%s "%s"  %s %s  %s %s%s\n' "$C_D" "$EQX_VERSION" "$EQX_CODENAME" "$S_DOT" "$(date '+%a %d %b %H:%M')" "$S_DOT" "$(eqx_os_name)" "$C_R"
  if eqx_battery_read 2>/dev/null; then printf '  %sbaterai %s%%%s\n' "$C_D" "$EQX_BAT_PCT" "$C_R"; fi
  [[ "${EQX_CFG[TIPS]}" == on || "${1:-}" == force ]] && { printf '\n  '; eqx_cmd_tips; }
  printf '\n'
}

# =============================================================================
# 17. HIBURAN
# =============================================================================
declare -ga EQX_QUOTES=(
  "Kode yang baik adalah dokumentasi terbaiknya sendiri."
  "Jangan takut gagal; takutlah tidak pernah mencoba."
  "Premature optimization is the root of all evil. - Donald Knuth"
  "Program harus ditulis untuk dibaca manusia. - Harold Abelson"
  "Talk is cheap. Show me the code. - Linus Torvalds"
  "Sederhana itu sulit, tapi layak diperjuangkan."
  "Setiap ahli dulunya pemula."
  "Debugging itu seperti jadi detektif di film kriminal di mana kamu juga pelakunya."
  "Satu langkah kecil setiap hari mengalahkan satu lompatan yang tak pernah terjadi."
  "Unix adalah kesederhanaan. Butuh orang jenius untuk memahami kesederhanaannya. - Dennis Ritchie"
  "Kesabaran adalah kompiler terbaik untuk mimpi."
  "Backup dulu, bereksperimen kemudian."
  "Kegagalan adalah data, bukan vonis."
  "Belajar terminal: awalnya lambat, lalu tak terbendung."
)

eqx_cmd_quote() { printf '  %s"%s"%s\n' "$C_I$C_P" "${EQX_QUOTES[RANDOM % ${#EQX_QUOTES[@]}]}" "$C_R"; }

eqx_cmd_cow() { # [teks]
  local msg="${*:-Moo! Selamat datang di Equinox.}" l max=0
  local -a lines=()
  mapfile -t lines < <(printf '%s\n' "$msg" | fold -s -w 36)
  for l in "${lines[@]}"; do (( ${#l} > max )) && max=${#l}; done
  local bar; printf -v bar '%*s' "$(( max + 2 ))" ''
  printf ' %s\n' "${bar// /_}"
  local i n=${#lines[@]}
  for i in "${!lines[@]}"; do
    l="${lines[i]}"
    local pad; printf -v pad '%*s' "$(( max - ${#l} ))" ''
    if (( n == 1 )); then printf '< %s%s >\n' "$l" "$pad"
    elif (( i == 0 )); then printf '/ %s%s \\\n' "$l" "$pad"
    elif (( i == n - 1 )); then printf '\\ %s%s /\n' "$l" "$pad"
    else printf '| %s%s |\n' "$l" "$pad"; fi
  done
  printf ' %s\n' "${bar// /-}"
  printf '%s' "$C_A"
  cat <<'EOF'
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
EOF
  printf '%s' "$C_R"
}

eqx_cmd_dice() { # [jumlah] [sisi]
  local n="${1:-1}" s="${2:-6}" i sum=0 r out=""
  [[ "$n" =~ ^[0-9]+$ && "$s" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 20 && s >= 2 && s <= 1000 )) || { eqx_err "pakai: eqx dice [jumlah 1-20] [sisi 2-1000]"; return 1; }
  for (( i = 0; i < n; i++ )); do r=$(( RANDOM % s + 1 )); sum=$(( sum + r )); out+="[$r] "; done
  printf '  %s%s%s total: %s%d%s\n' "$C_P" "$out" "$C_R" "$C_B" "$sum" "$C_R"
}

eqx_cmd_coin() { if (( RANDOM % 2 )); then eqx_info "Hasil: ANGKA"; else eqx_info "Hasil: GAMBAR"; fi; }

eqx_cmd_guess() { # tebak angka
  local max="${1:-100}" secret tries=0 g
  [[ "$max" =~ ^[0-9]+$ ]] && (( max >= 5 && max <= 100000 )) || max=100
  secret=$(( RANDOM % max + 1 ))
  eqx_info "Aku memilih angka 1-$max. Tebak! (ketik 'q' untuk menyerah)"
  while :; do
    read -r -p "  tebakan> " g || return 0
    [[ "$g" == q ]] && { eqx_info "Jawabannya: $secret"; return 0; }
    [[ "$g" =~ ^[0-9]+$ ]] || { eqx_warn "masukkan angka"; continue; }
    tries=$(( tries + 1 ))
    if (( g < secret )); then eqx_info "terlalu kecil"
    elif (( g > secret )); then eqx_info "terlalu besar"
    else eqx_ok "Benar! Angkanya $secret, dalam $tries tebakan."; return 0; fi
  done
}

eqx_cmd_rainbow() { # teks (atau stdin)
  local -a pal=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201)
  local line i n=0 ch
  local np=${#pal[@]}
  _rb() {
    line="$1"
    for (( i = 0; i < ${#line}; i++ )); do
      ch="${line:i:1}"
      if (( EQX_COLOR )); then printf '\e[38;5;%sm%s' "${pal[n % np]}" "$ch"; else printf '%s' "$ch"; fi
      n=$(( n + 1 ))
    done
    printf '%s\n' "$C_R"
  }
  if [[ $# -gt 0 ]]; then _rb "$*"
  else while IFS= read -r l || [[ -n "$l" ]]; do _rb "$l"; done; fi
  unset -f _rb
}

eqx_cmd_matrix() {
  local cols rows c y key="" ch
  cols="$(eqx_cols)"; rows="$(eqx_rows)"
  local -a drop=() speed=()
  for (( c = 0; c < cols; c++ )); do drop[c]=$(( -(RANDOM % rows) )); speed[c]=$(( RANDOM % 3 + 1 )); done
  eqx_screen_enter
  local chars='abcdefghijklmnopqrstuvwxyz0123456789@#$%&*+=<>?'
  while (( ! EQX_STOP )); do
    local buf=""
    for (( c = 0; c < cols; c += 2 )); do
      y=${drop[c]}
      if (( y >= 0 && y < rows )); then
        ch="${chars:RANDOM % ${#chars}:1}"
        buf+=$'\e['"$(( y + 1 ));$(( c + 1 ))"'H\e[1;37m'"$ch"
        if (( y > 0 )); then ch="${chars:RANDOM % ${#chars}:1}"; buf+=$'\e['"$y;$(( c + 1 ))"'H\e[0;32m'"$ch"; fi
        if (( y > 6 )); then buf+=$'\e['"$(( y - 6 ));$(( c + 1 ))"'H\e[0m '; fi
      fi
      drop[c]=$(( y + speed[c] ))
      (( drop[c] > rows + 8 )) && { drop[c]=$(( -(RANDOM % (rows / 2 + 1)) )); speed[c]=$(( RANDOM % 3 + 1 )); }
    done
    printf '%s' "$buf"
    if read -rsn1 -t 0.06 key; then [[ "$key" == q || "$key" == Q ]] && break; fi
  done
  printf '\e[0m'
  eqx_screen_leave
}

# =============================================================================
# 18. PEMELIHARAAN
# =============================================================================
eqx_cmd_version() {
  printf '%s%s%s %s "%s"\n' "$C_B$C_P" "$EQX_NAME" "$C_R" "$EQX_VERSION" "$EQX_CODENAME"
  eqx_kv "Bash" "$BASH_VERSION" 10
  eqx_kv "Platform" "$(eqx_os_name) / $EQX_ARCH" 10
  eqx_kv "Lokasi inti" "$EQX_SELF" 10
  eqx_kv "Repo" "$EQX_REPO_URL" 10
}

eqx_cmd_reload() {
  eqx_cfg_load
  eqx_symbols_init
  eqx_theme_apply "${EQX_CFG[THEME]}"
  if [[ $- == *i* ]]; then
    eqx_define_aliases
    eqx_plugins_load
    eqx_build_prompt 0
    HISTSIZE="${EQX_CFG[HIST_SIZE]}"; HISTFILESIZE="${EQX_CFG[HIST_SIZE]}"
  fi
  eqx_ok "Equinox dimuat ulang"
}

eqx_meta_get() { [[ -f "$EQX_META" ]] && sed -n "s/^$1=//p" "$EQX_META" | head -n1; }

eqx_cmd_update() {
  eqx_title "Pembaruan Equinox"
  local repo inst; repo="$(eqx_meta_get REPO_DIR)"
  inst="$EQX_LIB/installer.sh"
  if [[ -n "$repo" && -d "$repo/.git" ]] && eqx_have git; then
    eqx_info "Menarik pembaruan di $repo"
    local br="${EQX_CFG[UPDATE_BRANCH]}"
    if ! git -C "$repo" pull --ff-only origin "$br" 2>&1 | sed 's/^/    /'; then
      eqx_err "git pull gagal. Cek koneksi atau ubah branch: eqx config set UPDATE_BRANCH master"; return 1
    fi
    if [[ -f "$repo/Installer.sh" ]]; then
      eqx_info "Memasang ulang dari repo..."
      bash "$repo/Installer.sh" --update --yes && eqx_ok "Pembaruan selesai. Jalankan 'eqx reload' atau buka ulang shell."
      return
    fi
  fi
  if [[ -f "$inst" ]]; then
    eqx_info "Repo lokal tidak ditemukan; memakai installer terpasang untuk mengunduh dari GitHub."
    bash "$inst" --update --yes
  else
    eqx_err "tidak menemukan repo maupun installer. Clone ulang: git clone $EQX_REPO_URL"; return 1
  fi
}

eqx_cmd_uninstall() {
  local inst="$EQX_LIB/installer.sh"
  [[ -f "$inst" ]] || { eqx_err "installer tidak ditemukan di $EQX_LIB. Jalankan Installer.sh --uninstall dari folder repo."; return 1; }
  eqx_confirm "Copot instalasi Equinox?" n || { eqx_info "dibatalkan"; return 0; }
  bash "$inst" --uninstall
}

eqx_cmd_log() { # [n]|clear|path
  local sub="${1:-30}"
  [[ -f "$EQX_LOGFILE" ]] || { eqx_dim "  (log kosong)"; return 0; }
  case "$sub" in
    clear) : >"$EQX_LOGFILE"; eqx_ok "log dibersihkan" ;;
    path) printf '%s\n' "$EQX_LOGFILE" ;;
    *) [[ "$sub" =~ ^[0-9]+$ ]] || sub=30; tail -n "$sub" "$EQX_LOGFILE" ;;
  esac
}

# Uji mandiri: dipanggil `eqx selftest` atau oleh installer (--quiet)
eqx_cmd_selftest() {
  local quiet=0 pass=0 fail=0
  [[ "${1:-}" == --quiet ]] && quiet=1
  _t() { # nama harapan aktual
    if [[ "$2" == "$3" ]]; then pass=$(( pass + 1 )); (( quiet )) || printf '  %s%s%s %s\n' "$C_OK" "$S_OK" "$C_R" "$1"
    else fail=$(( fail + 1 )); printf '  %s%s%s %s (harap: %q, dapat: %q)\n' "$C_E" "$S_ERR" "$C_R" "$1" "$2" "$3"; fi
  }
  (( quiet )) || eqx_title "Uji Mandiri"
  _t "parse durasi 90" "90" "$(eqx_parse_duration 90)"
  _t "parse durasi 1m30s" "90" "$(eqx_parse_duration 1m30s)"
  _t "parse durasi 1h" "3600" "$(eqx_parse_duration 1h)"
  _t "parse durasi 2d" "172800" "$(eqx_parse_duration 2d)"
  _t "format durasi" "1h 1m" "$(eqx_dur 3660)"
  _t "format hms" "01:01:01" "$(eqx_hms 3661)"
  _t "ukuran manusia 1536" "1.5 KiB" "$(eqx_human 1536)"
  _t "ukuran manusia 5" "5 B" "$(eqx_human 5)"
  _t "calc 2+3*4" "14" "$(eqx_cmd_calc '2+3*4' 2>/dev/null)"
  _t "base64 enc" "ZXF4" "$(eqx_cmd_b64 enc eqx)"
  _t "base64 dec" "eqx" "$(eqx_cmd_b64 dec ZXF4)"
  _t "hash sha256" "064a5d42d2585fc17c774c2bcf7d6e35b371529344cfbccd4ffe7ea352824d2d" "$(eqx_cmd_hash -s equinox 2>/dev/null)"
  _t "url encode" "a%20b" "$(eqx_cmd_url enc 'a b')"
  _t "url decode" "a b" "$(eqx_cmd_url dec 'a%20b')"
  _t "validasi tema" "0" "$(eqx_cfg_validate THEME equinox >/dev/null; echo $?)"
  _t "validasi tema salah" "1" "$(eqx_cfg_validate THEME tidakada >/dev/null; echo $?)"
  # uji baca-tulis konfigurasi di file sementara
  local tmp old_conf="$EQX_CONF" old_theme="${EQX_CFG[THEME]}"
  tmp="$(eqx_tmpfile)"
  EQX_CONF="$tmp"; EQX_CFG[THEME]="nord"; eqx_cfg_save; EQX_CFG[THEME]="equinox"; eqx_cfg_load
  _t "config simpan/muat" "nord" "${EQX_CFG[THEME]}"
  EQX_CONF="$old_conf"; EQX_CFG[THEME]="$old_theme"; rm -f "$tmp"
  _t "direktori home dapat ditulis" "ya" "$([[ -w "$EQX_HOME" ]] && echo ya || echo tidak)"
  unset -f _t
  if (( fail == 0 )); then
    (( quiet )) || printf '\n'
    eqx_ok "Semua uji lulus ($pass)"
    return 0
  fi
  eqx_err "$fail uji gagal, $pass lulus"
  return 1
}

# =============================================================================
# 18b. EKSTRA: JARINGAN, SSH, UTILITAS
# =============================================================================
eqx_cmd_portcheck() { # host port [timeout]
  local host="${1:-}" port="${2:-}" to="${3:-4}"
  [[ "$host" =~ ^[A-Za-z0-9._-]+$ && "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) \
    || { eqx_err "pakai: eqx portcheck <host> <port> [timeout]"; return 1; }
  [[ "$to" =~ ^[0-9]+$ ]] || to=4
  if timeout "$to" bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null; then
    eqx_ok "$host:$port TERBUKA"
  else
    eqx_err "$host:$port tertutup atau tidak terjangkau"; return 1
  fi
}

eqx_cmd_wifi() {
  if eqx_have termux-wifi-connectioninfo; then
    local j; j="$(timeout 6 termux-wifi-connectioninfo 2>/dev/null)"
    [[ -n "$j" ]] || { eqx_warn "tidak ada respons dari Termux:API"; return 1; }
    local k v
    for k in ssid ip link_speed_mbps frequency_mhz rssi supplicant_state; do
      v="$(grep -o "\"$k\": *\"\?[^,\"}]*" <<<"$j" | head -n1 | sed 's/^[^:]*: *"\{0,1\}//')"
      [[ -n "$v" ]] && eqx_kv "$k" "$v" 18
    done
  else
    eqx_warn "butuh termux-api (eqx pkg install termux-api) + aplikasi Termux:API"
    eqx_kv "IP lokal" "$(eqx_local_ip)" 10
  fi
}

eqx_cmd_sshkey() { # create|show
  local sub="${1:-show}" k="$HOME/.ssh/id_ed25519"
  eqx_need ssh-keygen openssh || return 1
  case "$sub" in
    create)
      [[ -e "$k" ]] && { eqx_err "kunci sudah ada: $k"; return 1; }
      mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
      ssh-keygen -t ed25519 -f "$k" -C "$(id -un)@equinox" && eqx_ok "kunci dibuat: $k" ;;
    show)
      if [[ -f "$k.pub" ]]; then cat "$k.pub"; else eqx_err "belum ada kunci. Buat dengan: eqx sshkey create"; return 1; fi ;;
    *) eqx_err "subperintah: create | show"; return 1 ;;
  esac
}

eqx_cmd_sshd() { # start|stop|status
  local sub="${1:-status}" port=8022
  eqx_need sshd openssh || return 1
  case "$sub" in
    start)
      if pgrep -x sshd >/dev/null 2>&1; then eqx_info "sshd sudah berjalan"; else sshd && eqx_ok "sshd dimulai"; fi
      eqx_info "Sambung dari PC: ssh -p $port $(id -un)@$(eqx_local_ip)"
      eqx_dim "  Atur password dulu bila belum: passwd" ;;
    stop)
      pkill -x sshd >/dev/null 2>&1 && eqx_ok "sshd dihentikan" || eqx_warn "sshd tidak berjalan" ;;
    status)
      if pgrep -x sshd >/dev/null 2>&1; then eqx_ok "sshd berjalan"; else eqx_warn "sshd mati"; fi ;;
    *) eqx_err "subperintah: start | stop | status"; return 1 ;;
  esac
}

eqx_cmd_watch() { # detik perintah...
  local iv="${1:-}" key="" l
  [[ $# -ge 2 && "$iv" =~ ^[0-9]+$ ]] && (( iv >= 1 )) || { eqx_err "pakai: eqx watch <detik> <perintah...>"; return 1; }
  shift
  eqx_screen_enter
  while (( ! EQX_STOP )); do
    printf '\033[H'
    eqx_line "${C_D}setiap ${iv}s: $*   (q untuk keluar)${C_R}"
    "$@" 2>&1 | head -n "$(( $(eqx_rows) - 3 ))" | while IFS= read -r l; do eqx_line "$l"; done
    printf '\033[J'
    if read -rsn1 -t "$iv" key; then [[ "$key" == q || "$key" == Q ]] && break; fi
  done
  eqx_screen_leave
}

eqx_cmd_epoch() { # [angka-epoch | tanggal]
  local a="$*"
  if [[ -z "$a" ]]; then date +%s; return; fi
  if [[ "$a" =~ ^[0-9]{9,13}$ ]]; then
    (( ${#a} > 10 )) && a=$(( a / 1000 ))
    date -d "@$a" '+%Y-%m-%d %H:%M:%S %Z'
  else
    date -d "$a" +%s 2>/dev/null || { eqx_err "tanggal tidak dikenali: $a"; return 1; }
  fi
}

eqx_cmd_colors() {
  local i
  for i in {0..255}; do
    if (( EQX_COLOR )); then printf '\e[48;5;%sm%4s\e[0m' "$i" "$i"; else printf '%4s' "$i"; fi
    (( (i + 1) % 16 == 0 )) && printf '\n'
  done
}

eqx_cmd_json() { # [file]  (atau lewat pipe)
  local src="${1:--}" data
  if [[ "$src" == - ]]; then data="$(cat)"; else [[ -f "$src" ]] || { eqx_err "file tidak ada: $src"; return 1; }; data="$(<"$src")"; fi
  if eqx_have jq; then printf '%s' "$data" | jq .
  elif eqx_have python3; then printf '%s' "$data" | python3 -m json.tool
  else eqx_err "butuh jq atau python: eqx pkg install jq"; return 1; fi
}

eqx_cmd_count() { # berkas... | direktori
  [[ $# -ge 1 ]] || { eqx_err "pakai: eqx count <berkas|direktori...>"; return 1; }
  local t
  for t in "$@"; do
    if [[ -d "$t" ]]; then
      eqx_kv "$t" "$(find "$t" -type f 2>/dev/null | wc -l | tr -d ' ') file, $(find "$t" -type d 2>/dev/null | wc -l | tr -d ' ') folder" 24
    elif [[ -f "$t" ]]; then
      eqx_kv "$t" "$(wc -l <"$t" | tr -d ' ') baris, $(wc -w <"$t" | tr -d ' ') kata, $(eqx_human "$(wc -c <"$t")")" 24
    else eqx_warn "tidak ada: $t"; fi
  done
}

# =============================================================================
# 19. MENU INTERAKTIF
# =============================================================================
eqx_menu_run() { # perintah...  (jalankan lalu tunggu Enter)
  printf '\n'
  "$@"
  printf '\n%s[Enter] kembali ke menu%s' "$C_D" "$C_R"
  read -r _
}

eqx_menu_prompt_arg() { # pertanyaan -> stdout
  local a=""
  read -r -p "$(printf '%s?%s %s ' "$C_A" "$C_R" "$1")" a
  printf '%s' "$a"
}

eqx_cmd_menu() {
  [[ -t 0 ]] || { eqx_err "menu butuh terminal interaktif"; return 1; }
  local ch a
  while :; do
    printf '\033[2J\033[H'
    eqx_logo_small
    eqx_hr
    printf '  %s 1%s Info sistem        %s 2%s Monitor live       %s 3%s Penyimpanan\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s 4%s Cek jaringan       %s 5%s IP saya            %s 6%s Cuaca\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s 7%s Catatan            %s 8%s Todo               %s 9%s Pomodoro\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s10%s Password           %s11%s Backup HOME        %s12%s Bundle alat\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s13%s Ganti tema         %s14%s Gaya prompt        %s15%s Doctor\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s16%s Update paket       %s17%s Update Equinox     %s18%s Matrix\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s 0%s Keluar\n' "$C_E" "$C_R"
    eqx_hr
    read -r -p "$(printf '%s%s%s pilih> ' "$C_P" "$S_PROMPT" "$C_R")" ch || return 0
    case "$ch" in
      1) eqx_menu_run eqx_cmd_info ;;
      2) eqx_cmd_monitor ;;
      3) eqx_menu_run eqx_cmd_storage ;;
      4) eqx_menu_run eqx_cmd_net ;;
      5) eqx_menu_run eqx_cmd_ip ;;
      6) a="$(eqx_menu_prompt_arg 'Kota (kosong = otomatis):')"; eqx_menu_run eqx_cmd_weather $a ;;
      7) eqx_menu_run eqx_cmd_note list ;;
      8) eqx_menu_run eqx_cmd_todo list ;;
      9) eqx_cmd_pomodoro ;;
      10) a="$(eqx_menu_prompt_arg 'Panjang password [20]:')"; eqx_menu_run eqx_cmd_pass "${a:-20}" ;;
      11) eqx_menu_run eqx_cmd_backup create ;;
      12) eqx_menu_run eqx_cmd_tools list ;;
      13) eqx_cmd_theme list; a="$(eqx_menu_prompt_arg 'Nama tema:')"; [[ -n "$a" ]] && eqx_menu_run eqx_cmd_theme set "$a" ;;
      14) eqx_cmd_prompt list; a="$(eqx_menu_prompt_arg 'Nama gaya:')"; [[ -n "$a" ]] && eqx_menu_run eqx_cmd_prompt set "$a" ;;
      15) eqx_menu_run eqx_cmd_doctor ;;
      16) eqx_menu_run eqx_cmd_pkg upgrade ;;
      17) eqx_menu_run eqx_cmd_update ;;
      18) eqx_cmd_matrix ;;
      0|q|Q|exit) printf '\033[2J\033[H'; return 0 ;;
      *) ;;
    esac
  done
}

# =============================================================================
# 20. BANTUAN & REGISTRASI PERINTAH
# =============================================================================
EQX_CMDLIST=()
declare -gA EQX_CMD_CAT=() EQX_CMD_DESC=() EQX_CMD_USAGE=() EQX_CMD_SUBS=() EQX_CMD_ALIAS=()
EQX_CAT_ORDER=(system network files productivity tools security packages termux customize fun maintenance plugin)
declare -gA EQX_CAT_NAME=(
  [system]="Sistem" [network]="Jaringan" [files]="Berkas" [productivity]="Produktivitas"
  [tools]="Alat & Data" [security]="Keamanan" [packages]="Paket" [termux]="Termux"
  [customize]="Kustomisasi" [fun]="Hiburan" [maintenance]="Pemeliharaan" [plugin]="Plugin"
)

eqx_reg() { # nama kategori deskripsi [usage] [subs]
  local n="$1" x
  for x in "${EQX_CMDLIST[@]}"; do [[ "$x" == "$n" ]] && return 0; done
  EQX_CMDLIST+=("$n")
  EQX_CMD_CAT[$n]="$2"; EQX_CMD_DESC[$n]="$3"; EQX_CMD_USAGE[$n]="${4:-eqx $n}"; EQX_CMD_SUBS[$n]="${5:-}"
}

eqx_register_all() {
  # --- sistem
  eqx_reg info        system "Info sistem + logo (ala neofetch)"
  eqx_reg sys         system "Info sistem lengkap"
  eqx_reg mem         system "Pemakaian memori"
  eqx_reg battery     system "Status baterai"
  eqx_reg storage     system "Penyimpanan & folder terbesar"
  eqx_reg proc        system "Proses teratas" "eqx proc [jumlah] [mem|cpu]" "mem cpu"
  eqx_reg monitor     system "Monitor sistem live (q keluar)" "eqx monitor [detik]"
  eqx_reg clock       system "Jam digital besar"
  eqx_reg uptime      system "Waktu hidup perangkat"
  eqx_reg doctor      system "Periksa dependensi & lingkungan"
  eqx_reg env         system "Path & variabel Equinox"
  # --- jaringan
  eqx_reg ip          network "Alamat IP lokal/publik" "eqx ip [geo]" "geo"
  eqx_reg net         network "Tes konektivitas"
  eqx_reg speed       network "Tes kecepatan unduh" "eqx speed [MB]"
  eqx_reg ping        network "Ping host" "eqx ping [host] [jumlah]"
  eqx_reg weather     network "Cuaca (wttr.in)" "eqx weather [kota] [short]" "short"
  eqx_reg headers     network "Header HTTP sebuah URL" "eqx headers <url>"
  eqx_reg dns         network "Lookup DNS" "eqx dns <domain> [tipe]" "A AAAA MX TXT NS CNAME"
  eqx_reg ports       network "Port yang listen"
  eqx_reg serve       network "Server HTTP statis (python)" "eqx serve [port] [dir]"
  eqx_reg download    network "Unduh file (bisa dilanjutkan)" "eqx download <url> [nama]"
  # --- berkas
  eqx_reg usage       files "Pemakaian disk per folder" "eqx usage [dir] [jumlah]"
  eqx_reg big         files "File terbesar" "eqx big [dir] [jumlah]"
  eqx_reg ff          files "Cari file berdasarkan nama" "eqx ff <pola> [dir]"
  eqx_reg sr          files "Cari teks di dalam file" "eqx sr <teks> [dir]"
  eqx_reg tree        files "Pohon direktori" "eqx tree [dir] [kedalaman]"
  eqx_reg extract     files "Ekstrak berbagai arsip" "eqx extract <arsip...>"
  eqx_reg pack        files "Buat arsip" "eqx pack <nama.tar.gz|zip|tar.xz> <berkas...>"
  eqx_reg backup      files "Backup & pulihkan" "eqx backup [create|list|restore|prune]" "create list restore prune"
  eqx_reg dups        files "Temukan file duplikat" "eqx dups [dir]"
  eqx_reg trash       files "Tempat sampah aman" "eqx trash [put|list|restore|empty]" "put list restore empty"
  eqx_reg bm          files "Bookmark direktori" "eqx bm [add|go|list|del]" "add go list del"
  eqx_reg rename      files "Ganti nama massal (sed)" "eqx rename 's/lama/baru/' <berkas...>"
  eqx_reg calc        files "Kalkulator" "eqx calc '2+2*3'"
  # --- produktivitas
  eqx_reg note        productivity "Catatan cepat" "eqx note [add|list|show|del|search|edit|clear]" "add list show del search edit clear"
  eqx_reg todo        productivity "Daftar tugas" "eqx todo [add|list|done|undo|del|clear]" "add list done undo del clear"
  eqx_reg timer       productivity "Timer hitung mundur" "eqx timer <durasi> [pesan]"
  eqx_reg stopwatch   productivity "Stopwatch dengan putaran"
  eqx_reg pomodoro    productivity "Teknik pomodoro" "eqx pomodoro [kerja] [istirahat] [siklus]"
  eqx_reg hist        productivity "Statistik & cari riwayat" "eqx hist [top|search|stats|clear]" "top search stats clear"
  # --- alat data & keamanan
  eqx_reg pass        security "Generator password" "eqx pass [panjang] [jumlah] [--simple|--pin]" "--simple --pin"
  eqx_reg hash        security "Hash file/teks" "eqx hash [-a md5|sha1|sha256|sha512] <file> | -s <teks>"
  eqx_reg verify      security "Verifikasi hash file" "eqx verify <file> <hash>"
  eqx_reg crypt       security "Enkripsi/dekripsi file (AES-256)" "eqx crypt enc|dec <file>" "enc dec"
  eqx_reg b64         tools "Base64" "eqx b64 enc|dec <teks>" "enc dec"
  eqx_reg url         tools "URL encode/decode" "eqx url enc|dec <teks>" "enc dec"
  eqx_reg uuid        tools "Buat UUID" "eqx uuid [jumlah]"
  eqx_reg rand        tools "Angka acak" "eqx rand [min] [max]"
  eqx_reg portcheck   network "Cek port TCP terbuka/tidak" "eqx portcheck <host> <port>"
  eqx_reg wifi        network "Info Wi-Fi (Termux:API)"
  eqx_reg sshd        network "Kontrol server SSH Termux" "eqx sshd start|stop|status" "start stop status"
  eqx_reg sshkey      security "Buat/tampilkan kunci SSH ed25519" "eqx sshkey create|show" "create show"
  eqx_reg watch       system "Ulangi perintah tiap N detik" "eqx watch <detik> <perintah...>"
  eqx_reg epoch       tools "Konversi epoch <-> tanggal" "eqx epoch [angka|tanggal]"
  eqx_reg colors      tools "Palet 256 warna"
  eqx_reg json        tools "Rapikan JSON" "eqx json [file] (atau lewat pipe)"
  eqx_reg count       tools "Hitung baris/kata/file" "eqx count <berkas|dir...>"
  # --- paket
  eqx_reg pkg         packages "Pembungkus package manager" "eqx pkg install|remove|search|upgrade|list|info|clean" "install remove search upgrade list info clean count"
  eqx_reg tools       packages "Bundle paket siap pasang" "eqx tools list|install <bundle>|status" "list install status"
  eqx_reg git         packages "Ringkasan git & identitas" "eqx git [status|log|user]" "status log user"
  # --- termux
  eqx_reg termux      termux "Utilitas Termux & Termux:API" "eqx termux storage|reload|keys|api|notify|vibrate|toast|torch|clip" "storage reload keys api notify vibrate toast torch clip"
  # --- kustomisasi
  eqx_reg theme       customize "Kelola tema warna" "eqx theme list|set <nama>|preview [nama]" "list set preview current"
  eqx_reg prompt      customize "Gaya prompt" "eqx prompt list|set <gaya>|user <nama>" "list set user"
  eqx_reg alias       customize "Alias kustom" "eqx alias list|add <n> <perintah>|del <n>" "list add del"
  eqx_reg config      customize "Pengaturan Equinox" "eqx config list|get|set|reset|edit|path" "list get set reset edit path"
  eqx_reg plugin      customize "Kelola plugin" "eqx plugin list|enable|disable|new|dir" "list enable disable new dir"
  eqx_reg banner      customize "Tampilkan banner / teks besar" "eqx banner [teks]"
  eqx_reg tips        customize "Tips acak"
  # --- hiburan
  eqx_reg quote       fun "Kutipan acak"
  eqx_reg cow         fun "Sapi berbicara" "eqx cow [teks]"
  eqx_reg dice        fun "Lempar dadu" "eqx dice [jumlah] [sisi]"
  eqx_reg coin        fun "Lempar koin"
  eqx_reg guess       fun "Game tebak angka" "eqx guess [maks]"
  eqx_reg rainbow     fun "Teks berwarna pelangi" "eqx rainbow [teks] (atau lewat pipe)"
  eqx_reg matrix      fun "Animasi hujan Matrix (q keluar)"
  # --- pemeliharaan
  eqx_reg menu        maintenance "Menu interaktif"
  eqx_reg update      maintenance "Perbarui Equinox dari GitHub"
  eqx_reg reload      maintenance "Muat ulang konfigurasi, alias & plugin"
  eqx_reg version     maintenance "Versi & info build"
  eqx_reg selftest    maintenance "Uji mandiri inti Equinox"
  eqx_reg log         maintenance "Lihat log Equinox" "eqx log [n|clear|path]" "clear path"
  eqx_reg uninstall   maintenance "Copot Equinox"

  # alias perintah
  EQX_CMD_ALIAS=( [fetch]=info [neofetch]=info [sysinfo]=sys [i]=info [ver]=version [bat]=battery
                  [n]=note [t]=todo [p]=pkg [cfg]=config [free]=mem [top]=monitor [bookmark]=bm
                  [pw]=pass [password]=pass [cal]=calc [rm-safe]=trash [h]=help [-h]=help [--help]=help
                  [-v]=version [--version]=version [fortune]=quote [find]=ff [grep]=sr [search]=sr )
}

eqx_help_one() {
  local c="${1:-}"
  c="${EQX_CMD_ALIAS[$c]:-$c}"
  if [[ -z "${EQX_CMD_DESC[$c]:-}" ]]; then eqx_err "tidak ada bantuan untuk '$c'"; return 1; fi
  eqx_logo_small
  printf '\n  %s%s%s - %s\n' "$C_A" "$c" "$C_R" "${EQX_CMD_DESC[$c]}"
  printf '  Pemakaian : %s%s%s\n' "$C_P" "${EQX_CMD_USAGE[$c]}" "$C_R"
  [[ -n "${EQX_CMD_SUBS[$c]}" ]] && printf '  Opsi      : %s\n' "${EQX_CMD_SUBS[$c]}"
  local k a=""
  for k in "${!EQX_CMD_ALIAS[@]}"; do [[ "${EQX_CMD_ALIAS[$k]}" == "$c" && "$k" != -* ]] && a+="$k "; done
  [[ -n "$a" ]] && printf '  Alias     : %s\n' "$a"
  return 0
}

eqx_cmd_help() {
  if [[ -n "${1:-}" ]]; then eqx_help_one "$1"; return; fi
  eqx_logo_small
  printf '  Pemakaian: %seqx <perintah> [argumen]%s   |   %sequinox%s tanpa argumen = shell interaktif\n' "$C_P" "$C_R" "$C_P" "$C_R"
  printf '  Detail   : %seqx help <perintah>%s\n' "$C_P" "$C_R"
  local cat n shown
  for cat in "${EQX_CAT_ORDER[@]}"; do
    shown=0
    for n in "${EQX_CMDLIST[@]}"; do
      [[ "${EQX_CMD_CAT[$n]}" == "$cat" ]] || continue
      if (( ! shown )); then printf '\n%s%s%s\n' "$C_B$C_A" "${EQX_CAT_NAME[$cat]:-$cat}" "$C_R"; shown=1; fi
      printf '  %s%-11s%s %s\n' "$C_P" "$n" "$C_R" "${EQX_CMD_DESC[$n]}"
    done
  done
  printf '\n'
}

# =============================================================================
# 21. DISPATCHER
# =============================================================================
eqx_suggest() { # tebakan perintah
  local q="$1" n out=""
  for n in "${EQX_CMDLIST[@]}"; do
    [[ "$n" == "$q"* || "$n" == *"$q"* ]] && out+="$n "
  done
  [[ -n "$out" ]] && printf '%s' "$out"
}

eqx_main() {
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  [[ -z "$cmd" ]] && cmd="help"
  cmd="${EQX_CMD_ALIAS[$cmd]:-$cmd}"
  local fn="eqx_cmd_${cmd//-/_}"
  if declare -F "$fn" >/dev/null 2>&1; then
    "$fn" "$@"
    return $?
  fi
  eqx_err "perintah tidak dikenal: $cmd"
  local s; s="$(eqx_suggest "$cmd")"
  [[ -n "$s" ]] && eqx_info "mungkin maksud Anda: $s"
  eqx_dim "  Daftar perintah: eqx help"
  return 127
}

# =============================================================================
# 22. SHELL INTERAKTIF
# =============================================================================
eqx_interactive_init() {
  export EQUINOX_ACTIVE=1 EQUINOX_VERSION="$EQX_VERSION"
  # riwayat
  HISTFILE="$EQX_HISTFILE"
  HISTSIZE="${EQX_CFG[HIST_SIZE]}"; HISTFILESIZE="${EQX_CFG[HIST_SIZE]}"
  HISTCONTROL="ignoreboth:erasedups"
  HISTIGNORE="ls:ll:la:cd:pwd:clear:exit:history"
  shopt -s histappend cmdhist checkwinsize cdspell dirspell autocd 2>/dev/null
  shopt -s globstar nocaseglob 2>/dev/null
  [[ -f "$HISTFILE" ]] && history -r "$HISTFILE" 2>/dev/null
  bind 'set completion-ignore-case on' 2>/dev/null
  bind 'set show-all-if-ambiguous on' 2>/dev/null
  bind 'set colored-stats on' 2>/dev/null
  bind '"\e[A": history-search-backward' 2>/dev/null
  bind '"\e[B": history-search-forward' 2>/dev/null
  # bashrc pengguna (opsional)
  if [[ "${EQX_CFG[LOAD_BASHRC]}" == on && -f "$HOME/.bashrc" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.bashrc" 2>/dev/null
  fi
  eqx_define_aliases
  eqx_define_functions
  eqx_plugins_load
  complete -F _eqx_complete eqx equinox 2>/dev/null
  # prompt
  local user_pc="${PROMPT_COMMAND:-}"
  eqx_build_prompt 0
  if [[ -n "$user_pc" && "$user_pc" != *eqx_prompt_command* ]]; then
    PROMPT_COMMAND="eqx_prompt_command; ${user_pc}"
  else
    PROMPT_COMMAND="eqx_prompt_command"
  fi
  eqx_banner
}

# =============================================================================
# 23. TITIK MASUK
# =============================================================================
eqx_entry() {
  eqx_bootstrap
  eqx_register_all
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # dimuat via source / --rcfile
    [[ $- == *i* ]] && eqx_interactive_init
    return 0
  fi
  # dijalankan langsung
  eqx_plugins_load
  if [[ $# -eq 0 ]]; then
    exec "$BASH" --rcfile "$EQX_SELF" -i
  fi
  eqx_main "$@"
  exit $?
}

eqx_entry "$@"

