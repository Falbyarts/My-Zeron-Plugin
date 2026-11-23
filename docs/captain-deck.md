# Captain Deck

**Captain Deck** adalah plugin orkestrasi multi-agent *native* untuk **Zeron** yang **100% harness-agnostic** — tidak terikat pada harness tertentu seperti Pi, Claude Code, Codex, Antigravity/AGY CLI, OpenCode, Hermes, Cursor, atau agent ACP lainnya. Apa pun harness yang aktif di Zeron, kamu tetap bisa mengorkestrasi semuanya dari satu dek kontrol yang jelas dan visual.

Terinspirasi dari alur kerja **Capy Captains** (Captain jangka panjang + Attention Digest *"Needs You"* + Shared Rules) dan **bb Workflows** (Builder → Cross-Harness Reviewer, Fan-Out Swarm, dan manajemen worker lintas thread), seluruh mekanisme Captain Deck berjalan murni memakai API bawaan Zeron tanpa CLI tambahan dan tanpa mengirim data ke server luar.

---

## Fitur Utama

1. **Captains & Crew Tree (Hierarki Visual)**
   - **Promote chat mana pun** menjadi **Captain** (dari header chat, menu klik-kanan sidebar, atau tab **Chats** di Captain Deck), atau luncurkan Captain baru langsung dari halaman **Captain Deck**.
   - Spawn atau attach worker di bawah Captain dengan **harness & model bebas** per worker — misalnya Builder memakai OpenCode/Pi dan Reviewer memakai Antigravity/Claude Code.
   - Tampilan pohon Crew terindentasi memperlihatkan status live (`running`, `awaiting_input`, `completed`, `errored`), role, harness, pratinjau laporan terakhir, dan tombol **Steer / Queue** langsung di tempat.

2. **Attention Digest (*"Needs You"*) & Auto-Report Headless**
   - Service latar belakang (`service.luau`) mendengarkan event native Zeron (`turn.started`, `turn.finished`, `turn.errored`, `chat.awaiting_input`, `chat.input_answered`) untuk semua harness secara real-time.
   - Worker yang selesai otomatis mengirim ringkasan singkat ke Captain-nya (bisa diatur per Captain atau lewat Settings).
   - Kamu hanya diganggu notifikasi Zeron saat ada worker yang meminta input/approval, mengalami error/limit, atau saat Captain menandai item **Needs You**.

3. **Cross-Harness Workflows (1-Klik)**
   - **Build → Review:** worker Builder mengerjakan tugas di satu harness; begitu selesai dengan bersih, Captain Deck otomatis men-spawn worker Reviewer di harness lain dengan laporan Builder disisipkan.
   - **Fan-Out Swarm:** pecah daftar subtugas (satu per baris, hingga 8 worker) secara paralel di bawah satu Captain.
   - **Compare Harnesses:** jalankan prompt yang sama berdampingan di dua harness/model berbeda di bawah satu Captain.

4. **Side Panel Crew Inspector & Badges Native**
   - Badge kecil di sidebar (`.session-title`), baris ringkasan di hover card chat, dan pill di header chat untuk langsung membuka **Crew Inspector** di side panel tanpa meninggalkan percakapan.
   - Kelola **Mission**, **Shared Rules** (otomatis disisipkan ke prompt setiap worker baru), **Live Digest**, dan **Scheduled Wake** (bangunkan Captain tiap *N* menit).

5. **6 Native Agent Tools (`zeron.tool`)**
   - Setiap agent di harness mana pun otomatis mendapat akses ke tool orkestrasi Captain Deck:
     - `captain_status` — baca daftar Captain, Crew, status, laporan terakhir, rules, digest, dan item *Needs You*.
     - `captain_promote` — promosikan chat menjadi Captain.
     - `captain_spawn_worker` — spawn worker baru di harness/model/project/device mana pun (mendukung `handoff` otomatis).
     - `captain_message_worker` — kirim pesan `queue` atau `steer` ke worker/Captain.
     - `captain_attach_worker` — kaitkan chat yang sudah ada sebagai worker di bawah Captain.
     - `captain_update_digest` — perbarui mission/rules/digest atau eskalasi item **Needs You** ke manusia.

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
   https://github.com/Falbyarts/My-ZgX-Plugin/releases/tag/captain-deck-v1.0.1
   ```

2. Buka Zeron → **Settings** (ikon gerigi) → **Plugins** → klik **Install…**.
3. Tempel link di kolom **Link**, lalu klik **Install**.
4. Periksa daftar izin, lalu klik **Allow** / **Izinkan**.
5. Buka **Captain Deck** di sidebar kiri (atau tekan `Ctrl+Shift+O` / `Cmd+Shift+O`).

### Cara 2 — Lewat File `.zeron-plugin`

1. Buka [halaman rilis Captain Deck v1.0.1](https://github.com/Falbyarts/My-ZgX-Plugin/releases/tag/captain-deck-v1.0.1).
2. Di bagian **Assets**, unduh `captain-deck-1.0.1.zeron-plugin` *(jangan diekstrak)*.
3. Buka Zeron → **Settings** → **Plugins** → klik **Install…** → klik **Choose file…**.
4. Pilih file `captain-deck-1.0.1.zeron-plugin`.
5. Klik **Allow** / **Izinkan**, lalu buka **Captain Deck** di sidebar.

### Cara 3 — Langsung dari Repository GitHub *(Butuh Git)*

1. Pastikan Git terpasang di komputer.
2. Di Zeron, buka **Settings** → **Plugins** → klik **Install…**.
3. Tempel alamat berikut ke kolom **Link**, lalu klik **Install**:

   ```text
   https://github.com/Falbyarts/My-ZgX-Plugin/tree/main/plugins/captain-deck
   ```

4. Klik **Allow** / **Izinkan**.

---

## Pengaturan (Settings → Plugins → Captain Deck)

| Pengaturan | Default | Fungsi |
| --- | --- | --- |
| **Auto-report to Captain** | Aktif | Otomatis mengirim ringkasan laporan worker ke chat Captain saat turn selesai atau error. |
| **Attention notifications** | Aktif | Mengirim notifikasi Zeron saat worker menunggu input/approval, error, atau Captain menandai *Needs You*. |
| **Preferred reviewer harness** | Kosong (auto) | ID harness default untuk menu **Send to Cross-Harness Review…** (mis. `antigravity`, `opencode`, `claude-code`, `pi`, `hermes`). |
| **Show sidebar badges** | Aktif | Menampilkan badge `Captain` / `↳ role` di samping judul chat di sidebar. |
| **Show chat header controls** | Aktif | Menampilkan pill status orkestrasi atau tombol cepat **Captain** di header chat. |

---

## Izin yang Diminta

| Izin | Kegunaan |
| --- | --- |
| `ui.add` | Menampilkan badge di sidebar, baris hover card, pill header chat, dan menu klik-kanan chat. |
| `pages.add` | Menambahkan halaman **Captain Deck** di sidebar Zeron. |
| `panel.tabs` | Membuka tab **Crew Inspector** di side panel chat/halaman. |
| `navigate` | Lompat langsung ke chat Captain atau worker dalam satu klik. |
| `sessions.read` | Membaca daftar chat/project dan memantau event turn secara real-time. |
| `messages.read` | Membaca balasan terakhir worker pada `turn.finished` untuk laporan dan handoff otomatis. |
| `messages.send` | Membuat chat Captain/worker baru (`new_chat`), mengirim pesan/steer (`send_message`), dan auto-report ke Captain. |
| `models.read` | Membaca katalog model dari setiap harness yang tersedia di Zeron. |
| `notifications` | Mengirim notifikasi native Zeron saat ada item *Needs You*. |
| `service` | Menjalankan engine orkestrasi di latar belakang meskipun halaman Captain Deck sedang tidak dibuka. |
| `tools` | Mengekspos 6 tool orkestrasi agar agent di harness apa pun dapat mengorkestrasi worker. |

Tidak ada izin `commands` (shell), `network` (internet), atau `native` (binary eksternal).

---

## Troubleshooting

| Gejala | Solusi |
| --- | --- |
| Muncul banner *Orchestration service needs attention* | Pastikan plugin sudah diizinkan di **Settings → Plugins → Captain Deck → Allow**, lalu klik **Retry**. |
| Harness target gagal start saat spawn worker | Pastikan harness tersebut sudah terpasang dan login di Zeron (**Settings → Providers**). |
| Daftar model kosong untuk suatu harness | Klik tombol **Refresh** di kanan atas Captain Deck, atau ketik ID harness kustom di kolom *Custom harness id* lalu biarkan Model pada *Harness default*. |
| Auto-report berhenti setelah banyak giliran berturut-turut | Zeron memiliki *loop guard* bawaan (maksimal 16 pesan otomatis beruntun dari plugin tanpa balasan manusia). Kirim satu pesan manual di chat Captain untuk mereset hitungan. |
