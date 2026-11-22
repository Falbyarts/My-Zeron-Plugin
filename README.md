# My-Zeron-Plugin

Kumpulan plugin **Zeron** buatan Falbyarts (plugin komunitas, bukan bawaan resmi Zeron).

![Heatmap-LocLabs di bawah kotak chat New Chat](assets/heatmap-loclabs.png)

Semua plugin di repository ini gratis, *open-source*, dan berjalan **sepenuhnya di komputer lokal kamu**. Tidak ada riwayat commit atau data project yang dikirim ke server mana pun.

---

## Daftar Plugin

| Plugin | Ringkasan | Versi | Rilis & Panduan |
| --- | --- | --- | --- |
| **Heatmap-LocLabs** | Menampilkan heatmap commit Git lokal selama setahun terakhir tepat di bawah kotak chat **New Chat**. Arahkan kursor ke kotak berwarna untuk melihat daftar commit hari itu, dan klik ikon **refresh** kecil di samping jumlah commit untuk membaca ulang repo Git kapan saja. | `1.3.1` | [Panduan lengkap](docs/heatmap-loclabs.md) · [Halaman Rilis](https://github.com/Falbyarts/My-Zeron-Plugin/releases/tag/heatmap-loclabs-v1.3.1) |

---

## Cara Memasang Plugin

Sebelum mulai, pastikan:
- **Zeron** versi terbaru sudah terpasang dan terbuka.
- Ada koneksi internet untuk mengunduh plugin.
- Khusus **Heatmap-LocLabs**, **Git** harus sudah terpasang di komputer ([unduh Git untuk Windows](https://git-scm.com/download/win), lalu install seperti biasa).

Pilih **salah satu** dari tiga cara di bawah ini sesuai kebutuhanmu.

### Cara 1 — Lewat Link Rilis GitHub *(Disarankan & Paling Cepat)*

Zeron bisa langsung mengambil paket `.zeron-plugin` dari halaman rilis GitHub tanpa perlu mengunduh file secara manual.

1. Salin link rilis **Heatmap-LocLabs** berikut:

   ```text
   https://github.com/Falbyarts/My-Zeron-Plugin/releases/tag/heatmap-loclabs-v1.3.1
   ```

2. Di Zeron, buka **Settings** (ikon gerigi) → **Plugins** → klik **Install…**.
3. Tempel link tersebut ke kolom **Link**, lalu klik **Install**.
4. Zeron akan menampilkan daftar izin yang diminta plugin. Periksa sebentar, lalu klik **Allow** / **Izinkan**.
5. Buka **New Chat** — heatmap akan muncul di bawah kotak chat dan otomatis membaca jumlah commit lokalmu.

---

### Cara 2 — Lewat File `.zeron-plugin` *(Unduh Manual)*

Cocok jika kamu ingin menyimpan file installer plugin secara lokal atau memasangnya dari folder unduhan.

1. Buka [halaman rilis Heatmap-LocLabs v1.3.1](https://github.com/Falbyarts/My-Zeron-Plugin/releases/tag/heatmap-loclabs-v1.3.1).
2. Di bagian **Assets**, unduh file `heatmap-loclabs-1.3.1.zeron-plugin`.
   > **Jangan diekstrak.** File `.zeron-plugin` langsung dipasang lewat Zeron, bukan dibuka dengan WinRAR/7-Zip.
3. Di Zeron, buka **Settings** → **Plugins** → klik **Install…**.
4. Klik tombol **Choose file…**, lalu pilih file `heatmap-loclabs-1.3.1.zeron-plugin` yang tadi diunduh.
5. Klik **Allow** / **Izinkan** saat Zeron meminta persetujuan izin.
6. Buka **New Chat** untuk melihat hasilnya.

---

### Cara 3 — Langsung dari Repository GitHub *(Butuh Git, Mendukung Tombol Update)*

Cocok jika kamu ingin mengecek dan memasang pembaruan langsung lewat tombol **Update** di Zeron.

1. Pastikan **Git** sudah terpasang dan bisa dijalankan dari terminal (`git --version`).
2. Di Zeron, buka **Settings** → **Plugins** → klik **Install…**.
3. Tempel link folder plugin berikut ke kolom **Link**, lalu klik **Install**:

   ```text
   https://github.com/Falbyarts/My-Zeron-Plugin/tree/main/plugins/heatmap-loclabs
   ```

4. Klik **Allow** / **Izinkan** pada jendela izin.
5. Buka **New Chat** untuk melihat hasilnya.

---

## Cara Memperbarui & Menghapus Plugin

- **Memperbarui dari link rilis / file `.zeron-plugin`:** pasang versi baru dengan Cara 1 atau Cara 2 di atas — Zeron otomatis menimpa dan memperbarui plugin yang sama.
- **Memperbarui dari link repository (Cara 3):** buka **Settings** → **Plugins** → pilih **Heatmap-LocLabs** → klik **Update** bila tersedia.
- **Menghapus plugin:** buka **Settings** → **Plugins** → pilih **Heatmap-LocLabs** → klik **Remove** / **Hapus**. File project dan riwayat Git kamu tidak akan tersentuh.

---

## Troubleshooting

| Gejala | Solusi |
| --- | --- |
| Tombol **Install…** tidak ditemukan | Perbarui Zeron ke versi terbaru terlebih dahulu. |
| Muncul error `git_missing` | Pasang Git dari <https://git-scm.com/download/win>, lalu tutup dan buka kembali Zeron. |
| Muncul error `tampered` atau `other_signer` | Unduh ulang dari halaman rilis resmi repository ini. Jangan mengedit isi file plugin yang sudah ditandatangani. |
| Heatmap kosong (semua kotak abu-abu) | Pastikan folder project/chat yang terdaftar di Zeron adalah repo Git dan sudah memiliki minimal 1 commit. |
| Teks *"Reading your commits…"* tidak berubah | Pastikan Git terpasang (`git --version`), lalu klik ikon **refresh** kecil di samping tulisan tersebut. Jika masih gagal, buka ulang Zeron. |
| Muncul *"Allow Heatmap-LocLabs…"* | Plugin belum diizinkan. Buka **Settings** → **Plugins** → pilih **Heatmap-LocLabs** → klik **Allow**. |
| Kartu daftar commit tidak muncul saat hover | Pastikan kamu berada di halaman **New Chat**, lalu arahkan kursor tepat ke kotak hari yang berwarna dan diamkan sejenak. |

Masih menemukan kendala? Silakan buat **Issue** di repository ini dengan menyertakan versi Zeron, sistem operasi, dan pesan error yang muncul.

---

## Struktur Repository

```text
plugins/
  heatmap-loclabs/       Plugin Heatmap-LocLabs v1.3.1 (sudah ditandatangani & siap dipasang)
docs/
  heatmap-loclabs.md     Panduan lengkap penggunaan Heatmap-LocLabs
  development.md         Catatan alur kerja pemeliharaan plugin
assets/
  heatmap-loclabs.png    Pratinjau tampilan plugin
```

> Setiap folder di dalam `plugins/` adalah salinan plugin Zeron yang sudah ditandatangani secara kriptografis. Perubahan pada file di dalamnya akan membuat signature tidak cocok jika tidak ditandatangani ulang oleh Zeron.

---

## Privasi & Lisensi

- **100% Lokal:** Plugin hanya membaca riwayat commit Git pada folder project dan chat di komputer kamu sendiri. Tidak butuh login GitHub dan tidak mengirim data ke internet.
- **Lisensi:** [MIT](LICENSE) — bebas digunakan, dimodifikasi, dan dibagikan dengan tetap mencantumkan atribusi pembuatnya.
