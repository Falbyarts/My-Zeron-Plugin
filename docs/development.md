# Mengelola plugin dari dalam Zeron

Panduan ini untuk pemilik repo. Semua langkah bisa dilakukan dari Zeron, tanpa
keluar aplikasi.

## Kenapa plugin ada di dua tempat?

- **Folder hidup** — `%LOCALAPPDATA%\Zeron\plugins\<id>`: folder yang dibaca,
  ditandatangani, dan dijalankan Zeron.
- **Folder repo** — `plugins/<id>`: salinan persis untuk dibagikan lewat GitHub.

Zeron hanya memuat plugin dari folder hidup. Repo adalah tempat distribusi dan
cadangan, jadi arah sinkronnya selalu **folder hidup → repo**, bukan sebaliknya.

## Persiapan (sekali saja)

1. Pastikan folder `E:\zgx_plugin` sudah terdaftar sebagai project **zgx_plugin**
   di Zeron.
2. Setiap kali membuka chat untuk repo ini:
   - klik **New Chat**,
   - klik **No project** di bar bawah kotak chat,
   - pilih **zgx_plugin**,
   - pilih akses **Full access** (agar agent bisa menulis folder plugin Zeron
     dan menjalankan git).
3. `AGENTS.md` di root repo sudah berisi aturan kerja. Agent membacanya otomatis,
   jadi setiap chat baru mengikuti alur yang sama.

Tidak perlu `/init` atau slash command khusus. Cukup pilih project yang benar,
lalu bicara seperti biasa.

---

## Alur 1 — membuat plugin baru

1. **New Chat** → pilih project **zgx_plugin**.
2. Pastikan mode **Full access**.
3. Tempel prompt seperti ini (ganti bagian dalam kurung):

```text
Buat plugin Zeron baru.

id: <id-plugin>
nama: <Nama Plugin>
fungsi: <jelaskan singkat apa yang dilakukan plugin>
permissions: <daftar izin, misalnya ui.add, sessions.read>

Setelah plugin berjalan dan plugin_status bersih:
- salin foldernya ke plugins/<id-plugin>,
- tambahkan baris di tabel README,
- buat docs/<id-plugin>.md,
- verifikasi signature,
- commit dan push.
```

4. Saat Zeron menampilkan izin, klik **Allow / Izinkan**.
5. Cek hasilnya di **Settings → Plugins**, lalu buka **New Chat**.
6. Kalau sudah puas dan ingin dipublikasikan:

```text
Rilis plugin <id-plugin> versi <versi>.

Export plugin, buat release GitHub dengan tag <id-plugin>-v<versi>, unggah
asset .zeron-plugin, lalu pastikan repo bersih dan sudah di-push.
```

---

## Alur 2 — mengubah plugin yang sudah ada

```text
Ubah plugin <id-plugin>: <perubahan yang diinginkan>.

Setelah selesai:
- plugin_status harus bersih,
- naikkan versi di zeron-plugin.json,
- export plugin,
- salin ulang folder hidup ke plugins/<id-plugin>,
- verifikasi signature,
- commit, push, dan buat release baru.
```

Contoh nyata:

```text
Ubah plugin heatmap-loclabs: tampilkan nama branch di kartu commit.

Setelah selesai: plugin_status bersih, naikkan versi ke 1.2.1, export,
salin ke repo, verifikasi, commit, push, dan rilis heatmap-loclabs-v1.2.1.
```

---

## Alur 3 — hanya mengubah dokumentasi atau gambar

```text
Perbarui <file> di repo: <perubahan>.

Commit dengan pesan yang sesuai, lalu push.
```

Contoh:

```text
Ganti assets/heatmap-loclabs.png dengan gambar baru dari lampiran ini,
lalu commit dan push.
```

---

## Alur 4 — memperbarui plugin yang dipasang dari GitHub

Di Zeron:

1. Buka **Settings → Plugins**.
2. Pilih plugin yang mau diperbarui.
3. Klik **Update** kalau tersedia.
4. Setujui izin baru bila diminta.

Kalau plugin dipasang dari file `.zeron-plugin`, unduh versi baru dari halaman
release lalu pasang lagi; Zeron akan memperbaruinya.

---

## Apa yang terjadi di belakang layar

1. `create_plugin` membuat folder hidup di `%LOCALAPPDATA%\Zeron\plugins\<id>`
   dan menandatanganinya sebagai milikmu.
2. Agent mengedit `init.luau`, manifest, ikon, dan bahasa di folder hidup.
   Zeron menandatangani ulang setiap kali file disimpan.
3. `plugin_status` memeriksa plugin benar-benar tampil dan tidak error.
4. `export_plugin` membuat file `.zeron-plugin` bertanda tangan.
5. Agent menyalin folder hidup ke `plugins/<id>`, membandingkan SHA-256 setiap
   file, lalu commit dan push.
6. Release GitHub dibuat dan file `.zeron-plugin` diunggah sebagai asset.

---

## Kalau ingin manual tanpa AI

```powershell
cd E:\zgx_plugin

git status
git add -A
git commit -m "docs: perbarui panduan"
git push
```

`git push` memakai Git Credential Manager. Kalau muncul jendela login, pilih akun
**Falbyarts** dan setujui. Token tidak perlu diketik atau disimpan di file.

---

## Aturan versi dan nama rilis

| Perubahan | Contoh versi |
| --- | --- |
| Perbaikan kecil, teks, tampilan | 1.2.0 → 1.2.1 |
| Fitur baru | 1.2.0 → 1.3.0 |
| Perubahan besar / tidak kompatibel | 1.2.0 → 2.0.0 |

- Tag release: `<id>-v<versi>` → `heatmap-loclabs-v1.2.1`
- Nama asset: `<id>-<versi>.zeron-plugin` → `heatmap-loclabs-1.2.1.zeron-plugin`

---

## Troubleshooting

| Masalah | Solusi |
| --- | --- |
| Plugin berstatus **waiting** | Buka **Settings → Plugins**, pilih plugin, klik **Allow**. |
| Agent tidak bisa menulis folder plugin | Pastikan chat memakai **Full access** dan project **zgx_plugin**. |
| `signature_mismatches` bukan 0 | Jangan mengedit salinan di repo. Ulangi salin dari folder hidup, lalu verifikasi lagi. |
| Tombol **Update** tidak ada | Pasang ulang dari link release atau file `.zeron-plugin` versi baru. |
| `git push` meminta login | Pilih akun **Falbyarts** di jendela GCM. |
| Plugin tidak muncul di New Chat | Cek **Settings → Plugins** (harus **on**), lalu lihat pesan dari `plugin_status`. |
| Project tidak ditemukan | Pastikan `E:\zgx_plugin` terdaftar sebagai project di Zeron. |

---

## Checklist sebelum menutup chat

- [ ] `plugin_status` bersih (on, tanpa error).
- [ ] Versi di `zeron-plugin.json` sudah naik.
- [ ] `plugins/<id>` sudah disalin dan hash-nya cocok.
- [ ] README dan docs diperbarui.
- [ ] Commit dan push selesai.
- [ ] Release + asset `.zeron-plugin` sudah ada (kalau merilis).
