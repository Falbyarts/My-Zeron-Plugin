# Heatmap-LocLabs

![Contoh Heatmap-LocLabs di bawah kotak chat New Chat](../assets/heatmap-loclabs.png)

Heatmap-LocLabs menampilkan **satu tahun commit Git** sebagai kotak-kotak kecil
di bawah kotak chat **New Chat**. Setiap kotak adalah satu hari; makin terang
warnanya, makin banyak commit di hari itu.

Arahkan kursor ke kotak hari yang berwarna, dan muncul **kartu berisi daftar
commit** hari itu: tanggal lengkap, jumlah commit, jam, dan pesan commit-nya.

---

## Yang perlu disiapkan

1. **Zeron** versi 0.3.7 atau lebih baru.
2. **Git** terpasang di komputer (Windows, macOS, atau Linux).
   - Windows: <https://git-scm.com/download/win>
   - macOS: jalankan `git --version` di Terminal; kalau belum ada, install
     Xcode Command Line Tools.
   - Linux: install lewat package manager, misalnya `sudo apt install git`.
3. Sedikitnya satu folder project yang sudah menjadi **repo Git** dan punya
   commit.

> Plugin ini **tidak** memakai akun GitHub dan **tidak** mengirim data ke
> internet. Semua dibaca dari folder lokal di komputer ini.

---

## Cara memasang

### Paling mudah — lewat link rilis

1. Buka halaman rilis:

   <https://github.com/falbyarts/zeron-plugins/releases/tag/heatmap-loclabs-v1.2.0>

2. Salin alamat halaman itu dari address bar browser.
3. Buka Zeron → **Settings** (ikon gerigi) → **Plugins** → **Install…**
4. Tempel alamat tadi, lalu klik **Install**.
5. Baca izin yang diminta, lalu klik **Allow** / **Izinkan**.
6. Buka **New Chat**.

### Lewat file `.zeron-plugin`

1. Di halaman rilis, buka bagian **Assets**.
2. Unduh `heatmap-loclabs-1.2.0.zeron-plugin`.
3. Buka Zeron → **Settings** → **Plugins** → **Install…**
4. Pilih file yang baru diunduh.
5. Klik **Allow** / **Izinkan**.
6. Buka **New Chat**.

### Lewat source code (butuh Git)

Di **Settings** → **Plugins** → **Install…**, tempel:

```text
https://github.com/falbyarts/zeron-plugins/tree/main/plugins/heatmap-loclabs
```

---

## Cara memakai

1. Buka **New Chat** di Zeron.
2. Di bawah kotak chat akan muncul:
   - tulisan jumlah commit setahun terakhir,
   - label bulan (Jan, Feb, Mar, …),
   - label hari (Mon, Wed, Fri),
   - grid kotak-kotak harian,
   - keterangan **Less** dan **More**.
3. Kotak yang lebih terang berarti lebih banyak commit.
4. **Arahkan kursor** ke kotak hari yang berwarna.
5. Kartu akan muncul berisi:
   - tanggal lengkap (contoh: *Saturday, 07 November 2026*),
   - jumlah commit hari itu,
   - daftar commit, **terbaru di atas**, masing-masing dengan jam dan pesannya.

Kalau satu hari punya lebih dari 10 commit, kartu menampilkan 10 commit
terbaru lalu tulisan **+N more**.

> Heatmap hanya muncul di **New Chat**, bukan di halaman percakapan yang sedang
> berjalan. Ini supaya tidak mengganggu saat kamu mengetik atau membaca chat.

---

## Data apa yang dihitung?

- Folder yang dibaca adalah folder yang dipakai **chat dan project di Zeron**
  pada komputer ini.
- Perintah yang dipakai: `git log --all`, jadi commit dari **semua branch**
  ikut dihitung.
- **Semua email** ikut dihitung. Kalau kamu pernah mengganti email Git, commit
  lama dan baru tetap muncul.
- Satu commit dihitung satu kali, walaupun folder yang sama muncul di beberapa
  chat atau project.
- Jumlah folder maksimal 32, dan tiap hari disimpan maksimal 40 commit untuk
  daftar di kartu.
- Hasil disimpan selama **5 menit**. Membuka New Chat lagi setelah itu akan
  membaca ulang folder Git.

Yang **tidak** dibaca:

- Tidak ada file project yang dibaca — hanya riwayat commit Git.
- Tidak ada data dari GitHub, server, atau komputer lain.
- Commit yang dibuat di komputer lain tidak muncul di sini. Heatmap tiap
  komputer berisi commit komputer itu sendiri.

---

## Izin yang diminta

Saat memasang, Zeron menampilkan daftar izin. Untuk plugin ini artinya:

| Izin | Kenapa diperlukan |
| --- | --- |
| `ui.add` | Menggambar heatmap di bawah kotak chat. |
| `sessions.read` | Mengetahui folder chat dan project yang harus dibaca. |
| `service` | Menjalankan pembaca commit di latar belakang. |
| `commands: git` | Menjalankan `git log` di komputer ini. |

Tidak ada izin untuk mengirim pesan, membuka internet, atau mengubah file
project.

---

## Kalau tidak muncul atau error

### Heatmap kosong sama sekali

- Pastikan folder project di Zeron adalah repo Git:
  buka Terminal di folder itu, lalu jalankan `git status`.
- Pastikan repo punya commit:
  `git log --oneline -5`.
- Kalau folder belum menjadi repo, jalankan `git init`, buat commit pertama,
  lalu buka New Chat lagi.

### Tertulis “Reading your commits…” terus

- Git mungkin belum terpasang atau belum terbaca Zeron.
- Buka Terminal, jalankan `git --version`. Kalau muncul error, install Git.
- Setelah install Git, **tutup dan buka lagi Zeron**.

### Tertulis “Allow Heatmap-LocLabs…”

- Plugin ada, tetapi belum diizinkan.
- Buka **Settings** → **Plugins**, cari **Heatmap-LocLabs**, lalu izinkan
  (Allow).

### Muncul `git_missing` saat memasang

- Zeron belum menemukan Git. Install Git, lalu restart Zeron.

### Muncul `tampered` atau `other_signer`

- File plugin berubah atau bukan dari sumber resmi.
- Unduh ulang dari halaman rilis di repository ini, lalu pasang lagi.

### Kartu commit tidak muncul

- Pastikan kamu ada di **New Chat**.
- Arahkan kursor tepat ke kotak hari yang **berwarna** (bukan kotak kosong).
- Tunggu sekitar 0,2 detik; kartu muncul setelah kursor berhenti.

---

## Memperbarui plugin

- **Dipasang dari file:** unduh file versi baru dari halaman rilis, lalu
  **Settings** → **Plugins** → **Install…** dan pilih file baru. Zeron akan
  memperbarui plugin yang sama.
- **Dipasang dari link repo:** buka **Settings** → **Plugins**, pilih
  Heatmap-LocLabs, lalu klik **Update** (kalau tersedia).

Saat memperbarui, Zeron mungkin meminta izin lagi kalau ada izin baru.

## Menghapus plugin

**Settings** → **Plugins** → pilih **Heatmap-LocLabs** → **Remove** / **Hapus**.

Menghapus plugin juga menghapus data simpanannya. File project dan riwayat Git
kamu **tidak** terhapus.

---

## Riwayat versi

- **1.2.0** — kartu commit saat kursor diarahkan ke satu hari; tanggal, jumlah,
  jam, dan pesan commit.
- **1.1.0** — heatmap setahun di bawah kotak chat New Chat, mengikuti warna
  accent tema.

## Lisensi

[MIT](../LICENSE)
