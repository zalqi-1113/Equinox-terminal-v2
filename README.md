

# Equinox Linux Terminal

> Lingkungan terminal berbasis **Bash murni** untuk **Termux (Android)** — juga jalan di Linux biasa.
> Satu perintah `eqx` berisi 80+ utilitas: info sistem, monitor live, jaringan, manajemen berkas,
> catatan & todo, keamanan, manajer paket, tema, prompt cantik, plugin, dan lebih banyak lagi.

```
 ___    ___    _   _   ___   _  _    ___   __  __
| __|  / _ \  | | | | |_ _| | \| |  / _ \  \ \/ /
| _|  | (_) | | |_| |  | |  | .` | | (_) |  >  <
|___|  \__\_\  \___/  |___| |_|\_|  \___/  /_/\_\
```

---

## Daftar isi

1. [Instalasi cepat](#instalasi-cepat)
2. [Fitur utama](#fitur-utama)
3. [Cara pakai](#cara-pakai)
4. [Daftar perintah](#daftar-perintah)
5. [Tema & gaya prompt](#tema--gaya-prompt)
6. [Konfigurasi](#konfigurasi)
7. [Plugin](#plugin)
8. [Modul xxq](#modul-xxq)
9. [fallenAngel (reconnaissance & audit keamanan legal)](#fallenangel-reconnaissance--audit-keamanan-legal)
10. [Opsi Installer](#opsi-installer)
11. [Autostart](#autostart)
12. [Memperbarui & mencopot](#memperbarui--mencopot)
13. [Struktur repo & data](#struktur-repo--data)
14. [Pemecahan masalah](#pemecahan-masalah)
15. [FAQ](#faq)
16. [Kontribusi](#kontribusi)

---

## Instalasi cepat

Salin dan tempel di Termux:

```bash
git clone https://github.com/zalqi-1113/Equinox-terminal-v2.git && cd Equinox-terminal-v2 && bash installer.sh

```

Setelah selesai, jalankan:

```bash
equinox        # masuk ke shell interaktif Equinox
eqx help       # lihat semua perintah
```

Installer akan otomatis:

1. Mendeteksi lingkungan (Termux / Linux, package manager, lokasi pemasangan)
2. Memeriksa versi Bash, ruang disk, hak tulis, dan koneksi internet
3. Memasang dependensi yang kurang (`curl`, `gawk`, `procps`, `ncurses-utils`, dll.)
4. Mencari `equinox-core.sh` (lokal, atau mengunduh dari GitHub bila tidak ada)
5. Memvalidasi sintaks inti, mencadangkan instalasi lama, lalu menyalin berkas
6. Membuat perintah `equinox` dan `eqx`, metadata, serta konfigurasi awal
7. (Opsional) mengaktifkan autostart
8. Menjalankan uji verifikasi (sintaks, peluncur, *selftest*)

> **Pasang lengkap sekaligus** (nano, jq, tree, openssl, termux-api, git, zip, unzip + autostart):
> `./Installer.sh --yes --full --autostart`

---

## Fitur utama

| Kategori | Isi |
|---|---|
| **Shell interaktif** | Prompt dua baris dengan cabang git & kode error, riwayat persisten, alias, fungsi bantu, tab-completion untuk `eqx` |
| **Sistem** | `info` (gaya neofetch), `sys`, `mem`, `battery`, `storage`, `proc`, `monitor` live, `clock` besar, `doctor` |
| **Jaringan** | IP lokal/publik, tes koneksi, tes kecepatan, ping, cuaca, header HTTP, DNS, cek port, server HTTP, unduh dengan resume, SSH |
| **Berkas** | `usage`, `big`, `tree`, `extract`/`pack` (zip, tar.gz, 7z, ...), `backup`, deteksi duplikat, tempat sampah aman, bookmark folder, rename massal |
| **Produktivitas** | Catatan, todo berprioritas, timer, stopwatch, pomodoro, statistik riwayat |
| **Keamanan** | Generator password + estimasi entropi, hash/verify, enkripsi AES-256, kunci SSH |
| **Paket** | Pembungkus `pkg`/`apt`/`dnf`/`pacman`/`apk`/`zypper` + bundle siap pasang (`dev`, `net`, `term`, ...) |
| **Termux** | Izin storage, extra-keys preset, Termux:API (notifikasi, getar, clipboard, senter) |
| **Kustomisasi** | 8 tema warna, 6 gaya prompt, alias kustom, sistem plugin, banner teks sendiri (`xxq banner-custom`) |
| **Hiburan** | Matrix rain, cowsay, rainbow, dadu, koin, tebak angka, kutipan, `xxq hollywood`, `xxq typer` |
| **xxq** | Lapisan perintah ekstra khusus sesi Equinox (tidak ada di Termux biasa) — lihat [Modul xxq](#modul-xxq) |
| **fallenAngel** | Modul opsional reconnaissance & audit keamanan legal (`eqx install fallenAngel`) — lihat [bagian terkait](#fallenangel-reconnaissance--audit-keamanan-legal) |

Desain: **tanpa dependensi aneh** — hanya Bash 4.2+ dan utilitas standar (coreutils, curl, awk, sed, grep).

---

## Cara pakai

### Dua mode

```bash
equinox            # tanpa argumen  -> shell interaktif (prompt, alias, banner)
eqx info           # dengan argumen -> perintah tunggal (mode CLI)
```

Di dalam shell Equinox, `eqx` adalah fungsi, jadi cukup:

```bash
eqx help               # semua perintah
eqx help theme         # bantuan satu perintah
eqx menu               # menu interaktif bernomor
```

### Contoh sehari-hari

```bash
eqx info                          # ringkasan sistem + logo
eqx monitor                       # RAM/disk/baterai/proses live (tekan q)
eqx note "beli kuota"             # catatan cepat
eqx todo add "kirim laporan !tinggi"
eqx todo done 1
eqx timer 25m "fokus selesai"
eqx pass 24                       # password 24 karakter
eqx big ~ 20                      # 20 file terbesar di HOME
eqx backup create ~/proyek        # arsip .tar.gz ke ~/.equinox/backups
eqx trash put file.txt            # hapus aman (bisa dipulihkan)
eqx bm add proyek ~/proyek && eqx bm go proyek
eqx weather Jakarta
eqx speed 20                      # tes unduh 20 MB
eqx tools install dev             # python, nodejs, clang, make, cmake, git
```

### Alias & fungsi bawaan di shell interaktif

| Perintah | Fungsi |
|---|---|
| `ll`, `la`, `lt` | daftar berkas (detail / semua / urut waktu) |
| `..`, `...`, `up 3` | naik direktori |
| `mkcd nama` | buat folder lalu masuk |
| `bak file` | salin dengan stempel waktu |
| `psg nama` | cari proses |
| `hg kata` | cari di riwayat |
| `cheat tar` | contekan perintah (cheat.sh) |
| `extract arsip` | ekstrak otomatis berdasarkan ekstensi |
| `myip`, `ports`, `reload` | jalan pintas `eqx ip`, `eqx ports`, `eqx reload` |

---

## Daftar perintah

### Sistem
`info` · `sys` · `mem` · `battery` · `storage` · `proc [n] [mem|cpu]` · `monitor [detik]` · `clock` · `uptime` · `doctor` · `env` · `watch <detik> <perintah>`

### Jaringan
`ip [geo]` · `net` · `speed [MB]` · `ping [host] [n]` · `weather [kota] [short]` · `headers <url>` · `dns <domain> [tipe]` · `ports` · `portcheck <host> <port>` · `wifi` · `serve [port] [dir]` · `download <url> [nama]` · `sshd start|stop|status`

### Berkas
`usage [dir]` · `big [dir] [n]` · `ff <pola>` · `sr <teks>` · `tree [dir] [dalam]` · `extract` · `pack` · `backup [create|list|restore|prune]` · `dups [dir]` · `trash [put|list|restore|empty]` · `bm [add|go|list|del]` · `rename 's/a/b/' files` · `calc 'ekspresi'`

### Produktivitas
`note [add|list|show|del|search|edit|clear]` · `todo [add|list|done|undo|del|clear]` · `timer <durasi>` · `stopwatch` · `pomodoro [kerja] [istirahat] [siklus]` · `hist [top|search|stats|clear]`

### Keamanan & alat data
`pass [panjang] [jumlah] [--simple|--pin]` · `hash [-a algo] <file>|-s <teks>` · `verify <file> <hash>` · `crypt enc|dec <file>` · `sshkey create|show` · `b64 enc|dec` · `url enc|dec` · `uuid` · `rand` · `epoch` · `json` · `count` · `colors`

### Paket
`pkg install|remove|search|upgrade|list|info|clean|count` · `tools list|install <bundle>|status` · `git [status|log|user]`

### Termux
`termux storage|reload|keys [default|dev|mini]|api|notify|vibrate|toast|torch|clip`

### Kustomisasi
`theme list|set|preview` · `prompt list|set|user` · `alias list|add|del` · `config list|get|set|reset|edit|path` · `plugin list|enable|disable|new|dir` · `banner [teks]` · `tips`

### Hiburan
`quote` · `cow [teks]` · `dice [n] [sisi]` · `coin` · `guess [maks]` · `rainbow [teks]` · `matrix`

### Pemeliharaan
`menu` · `update` · `reload` · `version` · `selftest` · `log [n|clear|path]` · `uninstall`

**Alias singkat:** `fetch`/`neofetch`/`i` → `info`, `n` → `note`, `t` → `todo`, `p` → `pkg`, `top` → `monitor`, `pw` → `pass`, `cfg` → `config`.

---

## Tema & gaya prompt

**Tema** (`eqx theme set <nama>`): `equinox` · `aurora` · `ocean` · `sunset` · `matrix` · `dracula` · `nord` · `mono`

**Gaya prompt** (`eqx prompt set <gaya>`):

```
equinox   ╭─ equinox in ~/proyek ⎇ main            14:02
          ╰─❯
minimal   proyek ⎇ main ❯
classic   user@host:~/proyek$
hacker    ┌──(equinox@host)-[~/proyek]
          └─$
lean      14:02 equinox proyek ⎇ main ❯
arrow     ~/proyek ⎇ main ➜
```

Panah berubah merah dan menampilkan `✘kode` jika perintah terakhir gagal.
Jika font terminal tidak mendukung Unicode: `eqx config set UNICODE off`.

---

## Konfigurasi

File: `~/.equinox/equinox.conf` (format `KUNCI="nilai"`). Ubah lewat `eqx config set KUNCI nilai`, lalu `eqx reload`.

| Kunci | Default | Keterangan |
|---|---|---|
| `THEME` | `equinox` | tema warna |
| `PROMPT_STYLE` | `equinox` | gaya prompt |
| `PROMPT_USER` | *(kosong)* | nama di prompt (kosong = `equinox` di Termux, nama user di Linux) |
| `UNICODE` | `auto` | `auto` / `on` / `off` |
| `BANNER` | `on` | tampilkan logo saat shell dibuka |
| `TIPS` | `on` | tips acak di banner |
| `GIT_PROMPT` | `on` | tampilkan cabang git |
| `GIT_DIRTY` | `off` | tandai `*` jika ada perubahan (lebih lambat di repo besar) |
| `HIST_SIZE` | `5000` | ukuran riwayat |
| `LOAD_BASHRC` | `off` | ikut memuat `~/.bashrc` saat masuk shell Equinox |
| `WEATHER_CITY` | *(kosong)* | kota default untuk `eqx weather` |
| `EDITOR_CMD` | *(kosong)* | editor untuk `note edit` / `config edit` |
| `CONFIRM_DANGEROUS` | `on` | konfirmasi aksi berbahaya |
| `UPDATE_BRANCH` | `main` | branch untuk `eqx update` |
| `BANNER_CUSTOM` | *(kosong)* | teks banner kustom untuk `eqx info` (diatur lewat `xxq banner-custom`) |
| `HIBP_API_KEY` | *(kosong)* | API key Have I Been Pwned untuk `fa osint checkemail` |

Alias pribadi: `eqx alias add gs 'git status'` (disimpan di `~/.equinox/aliases.sh`).

---

## Plugin

Plugin adalah file `.sh` di `~/.equinox/plugins/`. Perintah plugin = fungsi `eqx_cmd_<nama>`:

```bash
eqx plugin new halo        # buat template
eqx reload
eqx halo dunia             # -> "Halo dari plugin halo! Argumen: dunia"
eqx plugin disable halo    # nonaktifkan (file jadi halo.sh.off)
```

Isi template:

```bash
eqx_cmd_halo() {
  eqx_ok "Halo dari plugin halo! Argumen: $*"
}
eqx_reg halo plugin "Plugin buatan sendiri: halo" "eqx halo [argumen]"
```

Fungsi bantu yang bisa dipakai plugin: `eqx_info`, `eqx_ok`, `eqx_warn`, `eqx_err`, `eqx_kv`, `eqx_bar`, `eqx_confirm`, `eqx_ask`, `eqx_run` (spinner), `eqx_have`, `eqx_human`, `eqx_cfg_get`.
> Hanya pasang plugin dari sumber yang Anda percaya — plugin dijalankan sebagai kode shell biasa.

---

## Modul xxq

`xxq` adalah lapisan perintah "ekstra" yang **hanya ada di dalam sesi Equinox** — di Termux
polos (sebelum masuk `equinox`), perintah `xxq` tidak dikenal. Ini sengaja jadi pembeda:
begitu Anda masuk Equinox, `xxq` tersedia sebagai perintah tersendiri.

```bash
xxq                         # daftar modul yang tersedia
xxq hollywood                # efek layar "hacker" dua panel ala film (q untuk keluar)
xxq typer                    # efek "hacker typer" komedi - tekan tombol apa saja
xxq banner-custom set "Toko Sejahtera"   # ganti teks banner di `eqx info`
xxq banner-custom preview    # lihat hasilnya
xxq banner-custom clear      # kembali ke logo Equinox bawaan
```

Catatan:
- `hollywood` dan `typer` **murni visual/komedi** — tidak membaca, mengubah, atau
  mengirim apa pun; aman dipakai untuk demo atau sekadar iseng.
- `banner-custom` dipakai juga oleh `eqx info` dan banner pembuka shell. Jika `figlet`
  terpasang (`eqx pkg install figlet`), teksnya dirender sebagai ASCII art besar;
  jika tidak, ditampilkan dalam kotak sederhana memakai warna tema aktif.
- `xxq <modul>` juga bisa dipanggil lewat `eqx xxq <modul>` di mode CLI non-interaktif.

---

## fallenAngel (reconnaissance & audit keamanan legal)

`eqx install fallenAngel` memasang modul keamanan **opsional** berisi perangkat
reconnaissance & audit yang legal. Modul ini **sengaja tidak berisi alat eksploitasi**
(tidak ada SQL injection, brute force login, pembuat payload, dsb.) — fokusnya murni pada
hal-hal yang sah: memasang lingkungan belajar (Kali), memindai jaringan milik sendiri,
mengaudit header keamanan situs sendiri, dan mengecek kebocoran data milik sendiri.

```bash
eqx install fallenAngel      # pasang modul (akan menampilkan & meminta persetujuan aturan pakai)
eqx fallenangel help         # atau: fa help   (alias pendek tersedia setelah terpasang)
```

### Submodul

| Perintah | Keterangan |
|---|---|
| `fa kali install\|enter\|status\|remove` | pasang/masuk **Kali Linux** lewat `proot-distro` — cara resmi Termux, bukan kode eksploitasi |
| `fa scan <target> [quick\|full\|service\|ping]` | pembungkus **nmap** (pemindaian port/servis informasional, bukan exploit) |
| `fa webaudit <url>` | audit **pasif/read-only**: header keamanan HTTP, sertifikat TLS, robots.txt/sitemap — situs **milik Anda sendiri** |
| `fa osint checkpass [sandi]` | cek apakah kata sandi pernah bocor, via API k-anonymity pwnedpasswords.com (sandi asli **tidak pernah dikirim**) |
| `fa osint checkemail <email>` | cek kebocoran akun lewat API Have I Been Pwned (butuh API key sendiri) |
| `fa authorize add\|remove\|list <target>` | daftarkan target yang **sudah Anda konfirmasi milik/izin Anda**, supaya `scan` tidak bertanya ulang tiap kali |
| `fa report new <target>\|list\|show <file>` | jalankan `webaudit`/`scan` lalu simpan hasilnya sebagai laporan teks di `~/.equinox/fallenangel-reports/` |
| `fa log [jumlah]` | lihat riwayat aktivitas modul ini (dicatat otomatis di log Equinox) |

### Aturan pakai (ditegakkan di kode, bukan cuma imbauan)

- `scan` **selalu** meminta konfirmasi eksplisit sebelum memindai target yang belum ada
  di daftar `authorize`, dan tidak bisa dilewati lewat pengaturan `CONFIRM_DANGEROUS`.
- Gunakan `scan` dan `webaudit` **hanya** pada sistem milik Anda sendiri, atau yang Anda
  miliki izin tertulis eksplisit untuk mengujinya. Memindai/menguji sistem orang lain
  tanpa izin dapat melanggar hukum (UU ITE, Computer Misuse Act, CFAA, dsb. — tergantung
  yurisdiksi Anda).
- `osint checkpass` tanpa argumen akan meminta kata sandi lewat prompt **tersembunyi**
  (tidak tercetak, tidak masuk riwayat perintah). Memberi sandi langsung sebagai argumen
  tetap didukung untuk scripting, tapi akan tercatat di riwayat shell — hindari jika bisa.
- Semua pemindaian dicatat ke `~/.equinox/logs/equinox.log` (lihat lewat `fa log`) sebagai
  jejak audit untuk Anda sendiri.

---

## Opsi Installer

```text
./Installer.sh [opsi]

  -y, --yes           setuju otomatis memasang dependensi
      --full          pasang juga nano, jq, tree, openssl, termux-api, git, zip, unzip
      --autostart     buka Equinox otomatis saat shell dibuka
      --no-autostart  jangan tanya autostart
      --update        perbarui inti saja (konfigurasi dipertahankan)
      --uninstall     copot Equinox   (+ --purge hapus data ~/.equinox)
      --check         periksa kesiapan sistem tanpa mengubah apa pun
      --no-deps       lewati pemasangan dependensi
      --offline       jangan unduh dari GitHub
      --download      paksa unduh inti terbaru dari GitHub
      --prefix DIR    pasang ke DIR (bin/ dan lib/equinox/)
  -v, --version       versi installer
  -h, --help          bantuan
```

Lokasi pemasangan otomatis: Termux → `$PREFIX`, Linux root → `/usr/local`, Linux biasa → `~/.local`.

---

## Autostart

Aktifkan lewat `./Installer.sh --autostart` (atau jawab *ya* saat ditanya). Installer menambahkan blok bertanda ke `~/.bashrc` (dengan backup otomatis). Perlindungan bawaan:

- Tidak masuk ke dalam dirinya sendiri (variabel `EQUINOX_ACTIVE`).
- Jika Equinox berhenti dalam < 3 detik (mis. error), Anda tetap mendapat shell biasa — **tidak akan terkunci**.
- Lewati sekali: `EQX_SKIP=1 bash`
- Matikan permanen tanpa edit file: `touch ~/.equinox/noautostart`

---

## Memperbarui & mencopot

```bash
eqx update                        # tarik dari GitHub lalu pasang ulang
# atau manual:
cd Equinox-Linux-Terminal- && git pull && ./Installer.sh --update
```

Instalasi lama otomatis dicadangkan di `~/.equinox/backups/install-<waktu>/`.

```bash
eqx uninstall                     # atau: ./Installer.sh --uninstall
./Installer.sh --uninstall --purge   # sekaligus hapus semua data pribadi
```

---

## Struktur repo & data

```text
Equinox-Linux-Terminal-/
├── Installer.sh        # pemasang (juga dipakai untuk update & uninstall)
├── equinox-core.sh     # inti Equinox (shell interaktif + semua perintah eqx)
└── README.md

# setelah terpasang (Termux: $PREFIX = /data/data/com.termux/files/usr)
$PREFIX/bin/equinox     # peluncur
$PREFIX/bin/eqx         # jalan pintas
$PREFIX/lib/equinox/    # equinox-core.sh, installer.sh, VERSION, README.md

~/.equinox/
├── equinox.conf        # konfigurasi
├── aliases.sh          # alias kustom
├── bookmarks.tsv       # bookmark folder
├── history             # riwayat perintah
├── install.meta        # info instalasi
├── notes/              # notes.tsv, todo.tsv
├── plugins/            # plugin *.sh
├── backups/            # arsip backup + cadangan instalasi
├── trash/              # tempat sampah aman
└── logs/               # equinox.log, install-*.log
```

---

## Pemecahan masalah

**`bad interpreter` / `permission denied` saat `./Installer.sh`**
Jalankan dengan `bash Installer.sh`. Jika masih gagal dan file pernah diedit di Windows, ubah baris baru: `sed -i 's/\r$//' Installer.sh equinox-core.sh`.

**`Perintah wajib belum ada` / gagal memasang paket**
Segarkan mirror Termux lalu ulangi: `termux-change-repo`, kemudian `pkg update -y` dan `./Installer.sh`.

**`equinox: command not found`**
Buka sesi Termux baru (atau `hash -r`). Cek `echo $PATH` memuat `$PREFIX/bin`.

**Karakter prompt berantakan (kotak/tanda tanya)**
Font tidak mendukung Unicode: `eqx config set UNICODE off && eqx reload`.

**Info baterai / notifikasi kosong**
Pasang paket `termux-api` **dan** aplikasi *Termux:API* (dari F-Droid), lalu `eqx termux api`.

**`eqx ports` / `eqx ip` kosong**
Android modern (10+) membatasi akses `/proc/net` dan `ip` bagi aplikasi biasa. Ini batasan sistem, bukan galat Equinox. `eqx ip` tetap menampilkan IP publik jika ada internet.

**`eqx update` gagal**
Cek koneksi. Jika branch default repo bukan `main`: `eqx config set UPDATE_BRANCH master`.

**Equinox bermasalah dan ingin kembali ke shell biasa**
`EQX_SKIP=1 bash` atau `touch ~/.equinox/noautostart`, lalu `./Installer.sh --uninstall`.

Diagnosis cepat: `eqx doctor`, `eqx selftest`, dan log di `~/.equinox/logs/`.

---

## FAQ

**Apakah butuh root?** Tidak. Seluruhnya berjalan sebagai pengguna Termux biasa.

**Apakah mengganti shell bawaan Termux?** Tidak. Equinox adalah Bash dengan `--rcfile` sendiri; `~/.bashrc` Anda tidak diubah kecuali Anda memilih autostart (dengan backup).

**Apakah bisa dipakai di Linux desktop/server?** Ya. Installer mendeteksi `apt`, `dnf`, `pacman`, `apk`, dan `zypper`. Untuk akun biasa, pemasangan ke `~/.local`.

**Data apa yang dikirim ke internet?** Tidak ada telemetri. Koneksi hanya terjadi saat Anda menjalankan perintah jaringan (`weather`, `ip`, `speed`, `update`, dll.) dan ke layanan publik yang tercantum di kode.

**Di mana saya bisa membaca kodenya?** Seluruh logika ada di `equinox-core.sh`, terbagi dalam seksi bernomor dengan komentar berbahasa Indonesia.

---

## Kontribusi

Issue dan pull request disambut di <https://github.com/zalqi-1113/Equinox-Linux-Terminal->.
Sebelum mengirim perubahan: `bash -n equinox-core.sh Installer.sh` dan `eqx selftest` harus lulus.

Dibuat oleh **zalqi-1113**.

