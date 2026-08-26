# PRD — Aplikasi Live Location Keluarga

> **Nama:** "FamLoc"
> **Versi:** 0.1 (Draft)
> **Tanggal:** 26 Agustus 2026
> **Status:** Menunggu review

---

## 1. Ringkasan Produk

Aplikasi mobile yang memungkinkan pengguna berbagi lokasi secara **real-time (live)** hanya dengan **teman terverifikasi** (mirip sistem pertemanan Facebook). Target utama adalah **sesama anggota keluarga** agar bisa saling memantau keberadaan — misalnya orang tua tahu posisi anak, anak tahu posisi orang tua yang sedang dalam perjalanan.

**Prinsip kunci:** privasi default. Lokasi HANYA terlihat oleh teman yang sudah saling accept, dan setiap pengguna punya kontrol penuh kapan sharing aktif/nonaktif.

---

## 2. Masalah & Latar Belakang

| Masalah | Solusi |
|---|---|
| Orang tua khawatir tidak tahu posisi anak (perjalanan, sekolah, pulang malam) | Live location antar anggota keluarga |
| Chat "dimana kamu?" berulang kali | Buka map, langsung terlihat |
| Aplikasi existing (Life360, GMaps sharing) kurang pas: mahal, terlalu kompleks, atau tidak ada sistem pertemanan mutual | Sistem teman mutual sederhana + sharing opt-in |
| Kekhawatiran privasi (dipantau terus-menerus) | Kontrol sharing manual + indikator "sedang dibagikan" |

---

## 3. Tujuan & Metrik Keberhasilan

### Tujuan
1. Pengguna dapat melihat lokasi live teman/keluarganya di satu peta.
2. Proses menambah teman cepat (< 30 detik) lewat QR code / link / kode undangan.
3. Akurasi & update lokasi cukup baik untuk kasus pemantauan keluarga (bukan navigasi).

### Metrik (contoh target MVP)
- Waktu dari install sampai lokasi pertama terlihat oleh teman < 5 menit.
- Update lokasi masuk dengan latensi rata-rata < 10 detik saat aplikasi aktif.
- Crash-free rate > 99%.

---

## 4. Persona

1. **Ayah/Ibu (Pemantau):** ingin tahu anak sudah sampai sekolah belum. Jarang buka app, butuh notifikasi.
2. **Anak Remaja/Dewasa (Dibagikan):** ingin privasi tapi mau orang tua tenang. Ingin bisa pause sharing sesekali.
3. **Keluarga jauh:** kakak/adik di kota lain yang tetap ingin saling lihat lokasi saat perjalanan.

---

## 5. Fitur

### 5.1 Fitur Inti (MVP)

#### F1 — Autentikasi
- Daftar/masuk dengan **email + password** (tanpa OTP — biaya Rp0).
- Profil dasar: nama, foto profil.
- Ganti password (verifikasi password lama dulu).

#### F2 — Sistem Pertemanan Mutual (ala Facebook)
- Cari pengguna lain → kirim **permintaan pertemanan**.
- Request harus **di-accept** oleh kedua pihak sebelum lokasi bisa dilihat (mutual).
- Status: `none → requested → friends`, plus opsi block/unfriend.
- Cara add yang ramah keluarga:
  - **QR code** (scan HP masing-masing) ← prioritas
  - **Link undangan** via WhatsApp → membuka **landing page statis di Vercel** berisi nama pengundang + kode undangan + tombol "Buka App"; jika app belum terinstall, kode bisa disalin manual
  - Pencarian email/nama

#### F3 — Live Location Sharing
- Setiap pengguna punya **saklar Sharing ON/OFF** (default OFF).
- Saat ON:
  - Lokasi dikirim ke server berkala (mis. tiap 5–15 detik saat app foreground; adaptif saat background).
  - Hanya teman mutual yang melihat posisi di peta.
- Saat OFF atau app ditutup: posisi terakhir terlihat dengan timestamp ("terakhir terlihat 12 menit lalu").
- **Status bergerak/diam**: marker/kartu menampilkan status turunan dari speed & heading — 🚗 Bergerak · 🏠 Diam · ⏸ Offline.
- **Status baterai**: level baterai pengguna dikirim bersama lokasi dan tampil di kartu teman (ala Life360) — membedakan "anak hilang" karena HP mati vs sharing dimatikan.
- Indikator jelas di UI bahwa "lokasimu sedang dibagikan ke N orang".
- **Mode presisi (toggle di Profil):** 📍 Akurat (default) atau 🌫️ Kasar (±500m). Pengaburan dilakukan SERVER sebelum data dikirim ke teman — posisi presisi tidak pernah keluar dari server saat mode kasar; pemilik selalu melihat posisi akuratnya sendiri.
- **Jadwal sharing otomatis:** pengguna bisa set jadwal (hari + jam mulai/selesai, mis. Sen–Jum 06.30–15.00); app menyalakan/mematikan sharing otomatis. Penjadwalan dieksekusi di CLIENT (Workmanager/AlarmManager) karena backend serverless tanpa timer; catatan: keandalan tergantung OS/vendor (lihat risiko autostart).
- **"Minta lokasi":** tombol di kartu teman offline → kirim permintaan halus "Ayah minta lihat lokasimu" → muncul sebagai notifikasi in-app di penerima dengan tombol "Nyalakan sharing" / abaikan. Tidak ada paksaan — penerima bebas menolak.
- **Deteksi fake GPS:** flag `is_mocked` dari sensor lokasi Android dikirim bersama posisi; jika true, marker teman ditandai ⚠️ "posisi mungkin tidak akurat" (tidak diblokir, hanya transparan).

#### F4 — Peta
- Peta dengan marker semua teman yang sedang sharing.
- Marker menampilkan nama + foto, tap → detail (akurasi, waktu update, alamat kasar).
- Alamat kasar = reverse geocoding **Nominatim OSM** (gratis, maks 1 req/dtk, hasil di-cache permanen di DB).
- Kartu teman menampilkan **jarak**: "2,4 km dari kamu" (dihitung dari data posisi yang sudah ada).
- Tombol "fokus ke saya" dan "fokus ke teman X".
- Screen **"Keluargaku"**: daftar semua teman mutual dengan status live/offline, baterai, status bergerak/diam, dan jarak.
- Refresh otomatis via **polling adaptif** (tiap 10 dtk saat map aktif/foreground; 30–60 dtk background) — tanpa WebSocket di MVP.

#### F5 — Notifikasi
- MVP: **notifikasi in-app** (badge/list di dalam app) saat: request teman baru, request di-accept.
- Fase 2: **push notification** (FCM + APNs) termasuk event teman mulai/berhenti sharing.
- (Fase 2) alert geofence: "Adik sudah tiba di rumah".

### 5.2 Fitur Fase 2 (Pasca-MVP)

| Fitur | Deskripsi |
|---|---|
| Grup keluarga | Buat grup "Keluarga Besar", lihat semua anggota di satu peta |
| Geofence/alert tempat | Notifikasi otomatis saat anggota tiba/pergi dari lokasi tersimpan (rumah, sekolah) |
| Riwayat lokasi | Timeline rute hari ini (opt-in) |
| Mode "hanya sementara" | Share lokasi hanya selama 1 jam / sampai tiba di tujuan |
| Emergency SOS | Tombol darurat kirim lokasi + notifikasi keras ke semua teman |
| Battery optimization tuning | Mode hemat baterai (update lebih jarang) |
| Push notification | FCM + APNs untuk semua jenis notifikasi |
| Hapus akun + ekspor data | Kepatuhan UU PDP: tombol hapus akun, semua data lokasi ikut terhapus |

### 5.3 Non-Fitur (Eksplisit tidak di MVP)
- Chat dalam aplikasi.
- Pelacakan diam-diam tanpa sepengetahuan pengguna (secara desain etis: yang dipantau SELALU bisa lihat status sharing dan mematikannya).
- Web dashboard.

---

## 6. Alur Utama (User Flow)

```
Daftar (email + password) → Lengkapi profil
    → Scan QR / share link → Kirim request → Diterima (mutual) ✅
    → Nyalakan saklar "Bagikan Lokasi"
    → Buka Peta → lihat marker teman yang juga sedang sharing
```

---

## 7. Persyaratan Fungsional (ringkas)

| ID | Requirement |
|---|---|
| RF-01 | Pengguna harus terautentikasi untuk semua fitur |
| RF-02 | Pertemanan wajib mutual (dua arah accept) sebelum lokasi terlihat |
| RF-03 | Lokasi hanya dikirim saat sharing ON; OFF = berhenti kirim & hapus dari peta real-time |
| RF-04 | Update posisi foreground ≤ 10 detik; background mengikuti batasan OS (Android FGM / iOS Significant Change) |
| RF-05 | Peta update realtime tanpa pull-to-refresh |
| RF-06 | Unfriend/block langsung menghapus akses lihat lokasi |
| RF-07 | Semua komunikasi via HTTPS; data lokasi tidak dijual/dibagikan ke pihak ketiga |

## 8. Persyaratan Non-Fungsional

- **Privasi:** lokasi disimpan sebagai riwayat terbatas (atau hanya posisi terakhir); enkripsi in-transit (TLS); ikuti UU PDP Indonesia.
- **Baterai:** mode update adaptif; transparan ke pengguna soal dampak baterai.
- **Performa peta:** halus ≥ 50 marker.
- **Offline handling:** tampilkan posisi terakhir + timestamp, retry otomatis.
- **Platform:** Android + iOS.

---

## 9. Arsitektur Teknis (usulan)

> **Keputusan teknologi (TERKUNCI):** Mobile = **Flutter** · Backend = **Node.js (Express)** di **Vercel** · Database = **Aiven PostgreSQL + PostGIS** · Realtime MVP = **Polling adaptif**.

| Komponen | Keputusan |
|---|---|
| Mobile app | **Flutter** |
| Map SDK | **flutter_map + tile OpenStreetMap** (gratis, tanpa API key) — bisa migrasi ke Google Maps/Mapbox nanti jika perlu |
| Realtime MVP | **Polling adaptif**: map aktif/foreground = tiap 10 dtk; background = 30–60 dtk. Tanpa WebSocket di MVP |
| Backend API | **Node.js (Express)** sebagai serverless functions di **Vercel** (free tier) |
| DB | **Aiven PostgreSQL + ekstensi PostGIS** (query "teman dalam radius") — sudah dimiliki user |
| Auth | **Email + password** (hash bcrypt, token JWT) — tanpa OTP agar biaya Rp0. Verifikasi email opsional fase 2. **Keputusan user:** email transaksional dikirim via SMTP Gmail pribadi (nodemailer + App Password); catatan risiko: limit ±500/hari, From ditulis ulang ke alamat Gmail, rawan spam — upgrade ke Brevo/Resend bila nanti jadi masalah |
| Push notification | **Fase 2** (FCM + APNs). MVP cukup notifikasi in-app — menghindari setup APNs/FCM yang kompleks di awal |
| Avatar | Disimpan di **Aiven PostgreSQL** (tabel `user_avatars`, kolom bytea). Client resize ke ±256px JPEG (<100KB) sebelum upload; dilayani via endpoint API dengan cache header |
| Reverse geocoding | **Nominatim OSM** (gratis) dengan cache permanen di tabel `geocode_cache` — hormati limit 1 req/dtk |
| Link undangan | Landing page statis di Vercel (kode undangan + tombol buka app); tanpa deep link native di MVP |
| Crash reporting | **Sentry free tier** di Flutter app |
| Sesi | **Multi-device diperbolehkan** (JWT valid sampai expired, tanpa invalidasi lintas perangkat) |
| Kebijakan privasi | Halaman statis di Vercel (wajib untuk Play Store): jelaskan data lokasi yang dikumpulkan, siapa yang bisa lihat, cara hapus akun |
| Upgrade path fase 2 | Tempel Ably/Pusher free tier untuk WebSocket tanpa rombak backend, atau pindah ke Railway bila butuh long-running server |

**Catatan teknis penting:**
- Background location di iOS ketat (harus ada justifikasi ke App Store); Android butuh Foreground Service + permission `ACCESS_BACKGROUND_LOCATION`.
- Untuk MVP, pola paling murah: client kirim titik ke backend tiap interval polling → simpan posisi terakhir di Postgres → teman mengambil posisi lewat endpoint polling yang sama (TANPA WebSocket).

---

## 10. Rencana Rilis

| Tahap | Isi | Estimasi |
|---|---|---|
| **MVP (v0.1)** | Auth, teman mutual + QR, sharing toggle (+status baterai & bergerak/diam), peta realtime polling, notifikasi in-app | 4–6 minggu |
| v0.2 | Grup keluarga, share sementara, battery mode | +3 minggu |
| v0.3 | Geofence alert, riwayat, SOS | +3–4 minggu |

## 11. Risiko

| Risiko | Mitigasi |
|---|---|
| Background location dibunuh OS (terutama Xiaomi/Oppo/ Vivo) | Edukasi user "izinkan autostart", dokumentasi per vendor |
| Penolakan App Store (iOS background location) | Justifikasi jelas + mode foreground-only di awal |
| Kepercayaan privasi pengguna | Toggle jelas, indikator sharing, tanpa hidden tracking |
| Biaya realtime/peta scale-up | Polling adaptif hemat kuota; monitoring kuota Vercel & Aiven; tile OSM sesuai usage policy |

## 12. Pertanyaan Terbuka

1. ~~OTP via SMS atau WhatsApp?~~ → DIPUTUSKAN: auth email + password tanpa OTP.
2. ~~Apakah riwayat lokasi perlu disimpan, atau cukup posisi terakhir?~~ → DIPUTUSKAN: cukup posisi TERAKHIR saja di MVP (sesuai skema `user_locations`); riwayat = fase 2 opt-in.
3. ~~Satu akun = satu orang, atau ada konsep "akun keluarga" dengan sub-akun anak?~~ → DIPUTUSKAN: satu akun = satu orang di MVP (setiap orang daftar dengan email sendiri); konsep sub-akun anak kecil dipertimbangkan di fase 2.
