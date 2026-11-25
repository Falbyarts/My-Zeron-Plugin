# Captain Deck

**Captain Deck** adalah plugin orkestrasi multi-agent *native* untuk **Zeron** yang **100% harness-agnostic** — tidak terikat pada harness tertentu seperti Pi, Claude Code, Codex, Antigravity/AGY CLI, OpenCode, Hermes, Cursor, atau agent ACP lainnya. Apa pun harness yang aktif di Zeron, kamu tetap bisa mengorkestrasi semuanya dari satu dek kontrol yang ringkas dan visual.

Terinspirasi dari alur kerja **Capy Captains** (Captain jangka panjang + Attention Digest *"Needs You"* + Shared Rules) dan **bb Workflows** (Builder → Cross-Harness Reviewer, Fan-Out Swarm, dan manajemen worker lintas thread), seluruh mekanisme Captain Deck berjalan murni memakai API bawaan Zeron tanpa CLI tambahan dan tanpa mengirim data ke server luar.

---

## Fitur Utama

1. **Floating Captain Deck di Atas Composer & Slash Command `/captain`**
   - Tidak memakan ruang sidebar — cukup ketik **`/captain`** di composer (ikut ter-scroll alami bersama daftar command `/` Zeron; ketik `/captain ` + spasi untuk buka cepat lewat keyboard) atau tekan **`Ctrl+Shift+O`** (`Cmd+Shift+O`).
   - Tampil sebagai **floating card solid** (`$popover.bg`) tepat di atas kotak composer dengan lebar adaptif, border aksen berputar ringan berbasis GPU shader, serta *smart click-outside dismiss* (klik area luar otomatis menutup kartu, kecuali ada draft misi/form yang sedang diisi agar tidak terbuang tanpa sengaja).
   - **4 tab ringkas:** `Fleet` | `Launch` | `Chats` | `Activity`, dengan panel sub-aksi inline (*Spawn Worker*, *Attach Chat*, *Edit Captain*, *Steer*, dan *Clear All*).

2. **Captains & Crew Tree + Bulk Clear All**
   - **Promote chat mana pun** menjadi **Captain** (dari menu klik-kanan sidebar atau tab **Chats** di Captain Deck), atau luncurkan misi baru langsung dari tab **Launch**.
   - Spawn atau attach worker di bawah Captain dengan **harness & model bebas** per worker — misalnya Builder memakai OpenCode/Pi dan Reviewer memakai Antigravity/Claude Code.
   - Kartu Captain bersih dengan **Live Digest** & **Shared Rules** vertikal *collapsible*, daftar Crew 2-baris dengan status live (`running`, `awaiting_input`, `completed`, `errored`), serta tombol hapus satu-per-satu maupun **`Clear All`** (dengan konfirmasi) untuk membersihkan seluruh orkestrasi & badge sekaligus.

3. **Cross-Harness Workflows & Lampiran Gambar/File Referensi**
   - **Build → Review:** worker Builder mengerjakan tugas di satu harness; begitu selesai dengan bersih, Captain Deck otomatis men-spawn worker Reviewer di harness lain dengan laporan Builder disisipkan.
   - **Parallel Swarm:** pecah daftar subtugas (satu per baris, hingga 8 worker) secara paralel di bawah satu Captain.
   - **Compare 2 Agents:** jalankan prompt yang sama berdampingan di dua harness/model berbeda di bawah satu Captain.
   - **New Captain:** buat Captain jangka panjang baru lengkap dengan misi dan Shared Rules.
   - Pemilih **Project** berada tepat di atas baris agen/model, dilengkapi *fallback* otomatis untuk `No specific project`.
   - **Dukungan gambar & file referensi** pada **Launch**, **Spawn Worker**, dan **Steer**: drag & drop file/gambar langsung ke area prompt atau tambahkan via path / **Paste Clipboard**, lengkap dengan thumbnail preview chip.

4. **Composer Orchestrator Bar Anti-Overlap, Crew Inspector Ramping & Judul Worker Ter-highlight di Sidebar**
   - **Composer Orchestrator Bar:** saat berada di chat Captain/Worker, tampil bar ringkas di atas composer dengan **in-flow bottom clearance** otomatis (sehingga baris streaming terbaru paling bawah dan dialog persetujuan tidak tertutup kartu), animasi status native Zeron (`working` / `input` / `failed` / `done`), panel **Permissions & Needs You** langsung di dalam kartu (`Allow` / `Deny` / `Open` / `Resolve`), serta akses cepat `Deck`, `Inspector`, dan `Hide` (bisa dimunculkan kembali 1-klik lewat restore pill mini).
   - **Sidebar Judul Worker & Badge Captain Adaptif Tema:** badge **Captain** selalu mengikuti warna aksen Zeron (`$accent`), sementara pada baris **Worker**, role worker ter-highlight (`↳ researcher`, `↳ builder`, `↳ verifier`) langsung menggantikan judul mentah yang sempit (`ui.change` pada `.session-title`) dengan kontras terbalik native (`$zeron.primary.bg` / `$zeron.primary.text`) sehingga rapi, rata kiri, dan jelas di mode gelap maupun terang.
   - **Side Panel Crew Inspector:** tampilan ramping fokus pada monitoring live, panel **Permissions & Needs You**, *Live Digest collapsible*, dan aksi cepat *Steer* / *Spawn Worker* / *Open Deck*.

5. **Permissions & Needs You (`chat.awaiting_input`), 6 Native Agent Tools & Skill Manual (`captain-deck-orchestrator`)**
   - Service latar belakang (`service.luau`) mendengarkan event native Zeron (`turn.started`, `turn.finished`, `turn.errored`, `chat.awaiting_input`, `chat.input_answered`) secara real-time, menangkap permintaan persetujuan/input agent untuk ditampilkan langsung di kartu conversation, Inspector, dan Deck (`Allow` / `Deny` lewat `zeron.answer` atau buka chat), auto-report ke Captain, dan mengirim notifikasi hanya saat butuh perhatianmu.
   - Setiap agent di harness mana pun otomatis mendapat 6 tool orkestrasi:
     - `captain_status` — baca daftar Captain, Crew, status, laporan terakhir, rules, digest, dan item *Needs You*.
     - `captain_promote` — promosikan chat menjadi Captain.
     - `captain_spawn_worker` — spawn worker baru di harness/model/project/device mana pun (mendukung `handoff` otomatis).
     - `captain_message_worker` — kirim pesan `queue` atau `steer` ke worker/Captain.
     - `captain_attach_worker` — kaitkan chat yang sudah ada sebagai worker di bawah Captain.
     - `captain_update_digest` — perbarui mission/rules/digest atau eskalasi item **Needs You** ke manusia.
   - Tersedia skill manual-trigger **`captain-deck-orchestrator`** ([`skills/captain-deck-orchestrator/SKILL.md`](../skills/captain-deck-orchestrator/SKILL.md)) agar agent langsung paham cara memakai ke-6 tool orkestrator tanpa menebak-nebak, dan **hanya aktif ketika diminta secara eksplisit** (tidak mengganggu delegasi subagent biasa).

---

## Persyaratan

- **Zeron** versi terbaru (0.3.15 atau lebih baru).
- Minimal satu harness agent yang sudah terpasang/aktif di Zeron (semakin banyak harness aktif, semakin fleksibel kombinasi cross-harness-nya).
- **Tidak perlu** CLI eksternal, Docker, atau akun pihak ketiga.

---

## Cara Memasang

Pilih salah satu cara berikut:

### Cara 1 — Lewat Link Rilis GitHub *(Disarankan)*

1. Salin link rilis berikut:

   ```text
   https://github.com/Falbyarts/My-ZgX-Plugin/releases/tag/captain-deck-v1.2.1
   ```

2. Buka Zeron → **Settings** (ikon gerigi) → **Plugins** → klik **Install…**.
3. Tempel link di kolom **Link**, lalu klik **Install**.
4. Periksa daftar izin, lalu klik **Allow** / **Izinkan**.
5. Ketik **`/captain`** di composer (atau tekan `Ctrl+Shift+O` / `Cmd+Shift+O`) untuk membuka floating card **Captain Deck**.

### Cara 2 — Lewat File `.zeron-plugin`

1. Buka [halaman rilis Captain Deck v1.2.1](https://github.com/Falbyarts/My-ZgX-Plugin/releases/tag/captain-deck-v1.2.1).
2. Di bagian **Assets**, unduh `captain-deck-1.2.1.zeron-plugin` *(jangan diekstrak)*.
3. Buka Zeron → **Settings** → **Plugins** → klik **Install…** → klik **Choose file…**.
4. Pilih file `captain-deck-1.2.1.zeron-plugin`.
5. Klik **Allow** / **Izinkan**, lalu ketik **`/captain`** di composer atau tekan `Ctrl+Shift+O` (`Cmd+Shift+O`).

### Cara 3 — Langsung dari Repository GitHub *(Butuh Git)*

1. Pastikan Git terpasang di komputer.
2. Di Zeron, buka **Settings** → **Plugins** → klik **Install…**.
3. Tempel alamat berikut ke kolom **Link**, lalu klik **Install**:

   ```text
   https://github.com/Falbyarts/My-ZgX-Plugin/tree/main/plugins/captain-deck
   ```

4. Klik **Allow** / **Izinkan**.

---

## Riwayat Pembaruan (Changelog)

### v1.2.1
- **Anti-Overlap Streaming Transcript:** Menambahkan *in-flow bottom clearance spacer* pada `#chat-session` yang mengikuti tinggi live **Composer Orchestrator Bar**, serta menaikkan batas tinggi composer hingga `720px` agar baris streaming terbaru paling bawah dan prompt persetujuan native tidak pernah tertutup kartu.
- **Animasi Status Native Zeron di Kartu Conversation:** Menghapus ikon grup statis di kartu conversation Captain/Worker (tetap dipertahankan di right-bar Inspector) dan menggantinya dengan animasi status bawaan Zeron (`@ds/status`: ring berputar saat *working*, *input*, *failed*, *done*).
- **Permissions & Needs You Langsung di Kartu, Inspector & Deck:** Menangkap detail `chat.awaiting_input` dan menambahkan RPC `answer_input` (`zeron.answer`) sehingga permintaan *human touch* / persetujuan agent tampil jelas di dalam kartu conversation, right-bar Crew Inspector, dan floating Captain Deck lengkap dengan tombol cepat `Allow` / `Deny` / `Open` / `Resolve`.
- **Judul Worker Ter-highlight & Rata di Sidebar:** Mengganti `.session-title` (`ui.change`) khusus baris worker agar role worker ter-highlight (`↳ researcher`, `↳ builder`, `↳ verifier`) menjadi judul utamanya tanpa teks terpotong `[Captain Rul...` dan tanpa label kanan yang tidak rata; prompt worker baru juga diawali header `[Worker: role] task`.
- **Skill Manual-Trigger `captain-deck-orchestrator`:** Menambahkan [`skills/captain-deck-orchestrator/SKILL.md`](../skills/captain-deck-orchestrator/SKILL.md) sebagai panduan terstruktur penggunaan ke-6 tool `captain_*` yang hanya aktif saat diminta secara eksplisit.

### v1.2.0
- **Floating Captain Deck Solid di Atas Composer & Slash Command `/captain`:** Menghapus halaman sidebar agar sidebar tetap rapi; Captain Deck kini dibuka sebagai *floating card* solid opaque (`$popover.bg`) tepat di atas composer lewat `/captain` (ter-scroll alami bersama daftar command `/` Zeron, plus pemicu keyboard `/captain ` + spasi) atau `Ctrl+Shift+O` (`Cmd+Shift+O`), lengkap dengan animasi border aksen berputar ringan berbasis GPU WGSL dan *smart click-outside dismiss* yang melindungi draft belum selesai.
- **Composer Orchestrator Bar & Restore Pill:** Menambahkan bar ringkas di atas composer untuk chat Captain/Worker dengan tombol `Deck`, `Inspector`, dan `Hide` yang mengecil menjadi restore pill mini (tidak hilang permanen), sekaligus menghapus kontrol header chat yang duplikat.
- **Desain Modern Fleet, Launch & Crew Inspector:** Memisahkan tab `Fleet` | `Launch` | `Chats` | `Activity`, memindahkan pemilih **Project** ke atas baris agen/model di tab `Launch`, memperbaiki tombol `+ Worker` ganda, merapikan kartu Captain dengan `Live Digest` vertikal *collapsible* serta daftar Crew 2-baris bersih, dan merampingkan **Crew Inspector** di side panel.
- **Warna Badge Adaptif Tema:** Badge **Captain** selalu mengikuti warna aksen Zeron (`$accent`), sementara badge **Worker** memakai kontras terbalik native (`$zeron.primary.bg` / `$zeron.primary.text`) di mode gelap maupun terang.
- **Dukungan Gambar/File Referensi & Bulk `Clear All`:** Menambahkan drag & drop / paste path / clipboard untuk melampirkan gambar dan file referensi pada `Launch`, `Spawn Worker`, dan `Steer`, serta tombol **`Clear All`** dengan konfirmasi inline untuk menghapus semua orkestrasi & badge sekaligus.
- **Perapian Pengaturan Plugin:** Mengubah **Preferred reviewer harness** menjadi dropdown pilihan resmi (`choice`) dengan sanitasi input lama, dan mengganti toggle header duplikat dengan **Show composer orchestrator bar**.

### v1.1.2
- **Launch Tanpa Project (`No specific project` Fallback):** Menambahkan *3-tier fallback* otomatis (`device` aktif → `fallback_project` sesi/project aktif → model default harness) pada `safe_new_chat`, sehingga semua mode (**Build → Review**, **Parallel Swarm**, **Compare 2 Agents**, **New Captain**, dan **Spawn Worker**) dapat langsung diluncurkan meskipun opsi **Project** dibiarkan pada `No specific project`.
- **Resilient Parallel Swarm & Compare:** Kegagalan pada salah satu worker paralel kini dicatat sebagai item **Needs You** tanpa membatalkan worker lain yang sudah berhasil di-spawn, serta batas waktu RPC peluncuran multi-agent diperpanjang menjadi 120 detik.

### v1.1.1
- **Fix Promise Chaining (`:after`) & Auto-Prune Ghost Chats:** Memperbaiki crash `attempt to index nil with 'after'` saat mempromosikan chat menjadi Captain, serta membersihkan Captain/Worker yang chat aslinya sudah dihapus di Zeron secara otomatis.
- **Perapian Tata Letak Quick Mission Composer & Dropdown Searchable:** Menggunakan `Dropdown` *searchable* dengan `menu_width = 400` agar nama model AI panjang tidak terpotong, serta merapikan grid dan jarak antar kartu mengikuti gaya bawaan Settings Zeron.

---

## Pengaturan (Settings → Plugins → Captain Deck)

| Pengaturan | Default | Fungsi |
| --- | --- | --- |
| **Auto-report to Captain** | Aktif | Otomatis mengirim ringkasan laporan worker ke chat Captain saat turn selesai atau error. |
| **Attention notifications** | Aktif | Mengirim notifikasi Zeron saat worker menunggu input/approval, error, atau Captain menandai *Needs You*. |
| **Preferred reviewer harness** | Auto | Dropdown pilihan harness default untuk **Cross-Harness Review** (`Auto`, `Antigravity`, `Claude Code`, `Codex`, `OpenCode`, `Pi`, `Hermes`). |
| **Show sidebar badges** | Aktif | Menampilkan badge `Captain` / `↳ role` di samping judul chat di sidebar. |
| **Show composer orchestrator bar** | Aktif | Menampilkan bar ringkas Captain/Crew di atas composer pada chat terorkestrasi dengan akses cepat ke Deck dan Crew Inspector. |

---

## Izin yang Diminta

| Izin | Kegunaan |
| --- | --- |
| `ui.add` | Menampilkan baris hover card, floating card & orchestrator bar di atas composer, *stream clearance spacer*, slash command `/captain`, dan menu klik-kanan chat. |
| `ui.change` | Mengganti judul baris chat di sidebar (`.session-title`) agar baris worker menampilkan role ter-highlight sebagai judul rapi dan baris Captain menampilkan judul + badge aksen. |
| `panel.tabs` | Membuka tab **Crew Inspector** di side panel chat. |
| `navigate` | Lompat langsung ke chat Captain atau worker dalam satu klik. |
| `draft` | Membaca teks draft composer secara lokal untuk mendeteksi pemicu slash command `/captain`. |
| `compose` | Membersihkan token `/captain` dari composer setelah kamu memilih atau mengetiknya. |
| `sessions.read` | Membaca daftar chat/project dan memantau event turn secara real-time. |
| `messages.read` | Membaca balasan terakhir worker pada `turn.finished` untuk laporan dan handoff otomatis. |
| `messages.send` | Membuat chat Captain/worker baru (`new_chat`), mengirim pesan/steer (`send_message`), dan auto-report ke Captain. |
| `models.read` | Membaca katalog model dari setiap harness yang tersedia di Zeron. |
| `files.read` | Melampirkan gambar atau file referensi yang kamu pilih/drop saat meluncurkan misi, men-spawn worker, atau melakukan steer. |
| `notifications` | Mengirim notifikasi native Zeron saat ada item *Needs You*. |
| `service` | Menjalankan engine orkestrasi di latar belakang meskipun floating card Captain Deck sedang ditutup. |
| `tools` | Mengekspos 6 tool orkestrasi agar agent di harness apa pun dapat mengorkestrasi worker. |

Tidak ada izin `commands` (shell), `network` (internet), atau `native` (binary eksternal).

---

## Troubleshooting

| Gejala | Solusi |
| --- | --- |
| Muncul banner *Orchestration service needs attention* | Pastikan plugin sudah diizinkan di **Settings → Plugins → Captain Deck → Allow**, lalu klik **Retry**. |
| Harness target gagal start saat spawn worker | Pastikan harness tersebut sudah terpasang dan login di Zeron (**Settings → Providers**). |
| Daftar model kosong untuk suatu harness | Klik tombol **Refresh** di kanan atas Captain Deck, atau biarkan Model pada *Harness default*. |
| Bar di atas composer disembunyikan | Klik **restore pill** mini (`Captain · N` / `Crew · role` dengan panah atas) di kanan atas composer untuk memunculkannya kembali. |
| Auto-report berhenti setelah banyak giliran berturut-turut | Zeron memiliki *loop guard* bawaan (maksimal 16 pesan otomatis beruntun dari plugin tanpa balasan manusia). Kirim satu pesan manual di chat Captain untuk mereset hitungan. |
