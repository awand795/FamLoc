# 📍 FamLoc — Family Live Location Tracker (Supabase Realtime)

**FamLoc** adalah aplikasi pelacak lokasi keluarga (khusus Anda dan keluarga tercinta) secara *realtime*, privat, hemat daya, dan bebas biaya server. Dibangun langsung menggunakan **Flutter** dan **Supabase Realtime (WebSocket)** tanpa perlu mengelola server backend terpisah.

---

## ✨ Fitur Lengkap Aplikasi

- 🚀 **Realtime Live Tracking (WebSocket)**: Pergerakan lokasi anggota keluarga di peta disiarkan secara instan (<100ms latency) melalui koneksi WebSocket persisten bawaan Supabase (`supabase_flutter`).
- 🗺️ **Tampilan Peta Multi-Layer & Dark Mode**:
  - **Mode Default**: Peta Jalan Google Maps bersih & modern.
  - **Mode Satelit**: Foto Udara Satelit Nyata Google Maps (dengan nama jalan).
  - **Mode Terrain**: Peta Kontur Topografi Ketinggian Tanah.
  - **Mode Malam (Dark Mode)**: Peta gelap kontras tinggi, sangat nyaman di mata untuk perjalanan malam dan hemat daya di layar AMOLED.
- 🏠 **Notifikasi Zona Aman (Geofencing Rumah & Kantor)**:
  - Buat dan tandai tempat favorit (Rumah, Kantor, Sekolah, Pasar).
  - Peta otomatis menampilkan lingkaran geofence transparan.
  - Aplikasi otomatis memunculkan notifikasi saat keluarga tiba atau meninggalkan zona: *"Mama sudah tiba di Rumah 🏡"*.
- 📜 **Rekam Jejak Rute Hari Ini (Breadcrumb Trail)**:
  - Tombol *"Lihat Jejak Rute Hari Ini"* untuk menggambar garis biru rute yang telah dilalui dari pagi hingga malam.
- 💬 **Kabar Kilat 1-Ketukan (Quick Check-in)**:
  - Siarkan pesan instan ke HP keluarga tanpa repot mengetik: *"Aku sudah sampai ya!"*, *"Sedang jalan pulang"*, *"Tolong jemput"*, dll.
- 🎥 **Auto-Follow Kamera Realtime**: Kamera peta otomatis meluncur dan mengikuti pergerakan Mama/keluarga di jalan secara langsung saat difokuskan.
- 🧭 **Petunjuk Arah 1-Ketukan (Buka Google Maps)**: Tombol *"Rute Maps"* yang langsung membuka aplikasi Google Maps di HP dengan rute navigasi tercepat dan estimasi waktu sampai (ETA).
- 🚨 **Sinyal Darurat SOS Realtime**: Tombol darurat SOS merah yang seketika menyiarkan peringatan darurat ke seluruh anggota keluarga dengan koordinat presisi dan tombol respon cepat.
- 🚗 **Speedometer & Status Gerak Cerdas**: Mendeteksi otomatis apakah keluarga sedang *Berkendara (km/jam)*, *Berjalan Kaki*, atau *Berhenti/Diam*.
- 🔋 **Live Battery Badge & Peringatan Otomatis**:
  - Persentase baterai HP keluarga tampil langsung di atas marker peta (`Mama 🔋 85%`).
  - Notifikasi otomatis saat baterai HP keluarga $\le 15\%$ agar segera diingatkan untuk mengecas.
- ⏱️ **Deteksi Arah & Estimasi Waktu Tiba Cerdas (Dynamic ETA)**:
  - Berdasarkan vektor pergerakan arah kompas dan penurunan jarak, aplikasi mendeteksi otomatis jika keluarga sedang melaju menuju *Rumah*, *Kost*, atau *Kantor*, lalu menghitung estimasi waktu tiba secara presisi (*"🚗 Menuju Rumah · Sisa 3.5 km · ETA ~6 mnt"*).
- ⚠️ **Peringatan Melaju Cepat (Speed Limit Alert)**:
  - Notifikasi otomatis di kedua HP saat kendaraan melaju di atas kecepatan aman ($> 80 \text{ km/jam}$) untuk menjaga keselamatan berkendara di jalan.
- 📞 **Pintasan Langsung Telepon & Chat WhatsApp**:
  - Tombol 1-ketukan untuk langsung menelepon nomor HP keluarga atau membuka obrolan pesan WhatsApp tanpa perlu mencari kontak secara manual.
- 🔊 **Fitur Deringkan HP / Cari HP Lupa Taruh (Find My Device)**:
  - Tombol untuk membunyikan HP keluarga dengan dering kencang terus-menerus selama 30 detik (meskipun HP disetel mode Hening / Silent) agar posisinya di rumah/kamar segera ditemukan.
- 🔔 **Notifikasi Layar Kunci & Getar/Suara (Lock Screen Popups)**:
  - Notifikasi penting (Tiba/Keluar Zona, Sinyal Darurat SOS, Pesan Kabar Kilat, dan Peringatan Baterai Lemah) **otomatis menyala, berdering, bergetar, dan muncul di layar kunci HP** meskipun layar HP sedang mati/terkunci (menggunakan *Android High Importance Notification Channels*).
- 🔒 **Pelacakan Latar Belakang Penuh (Android 14+ & Screen-Off WakeLock)**:
  - Lokasi tetap terkirim secara realtime saat HP di dalam kantong celana atau saat layar HP dimatikan/terkunci di perjalanan.
  - Dilengkapi *Foreground Service* dengan notifikasi status bar dan dukungan sistem Android 10, 11, 12, 13, 14, hingga 15.
- 🛡️ **Privasi & Keamanan Penuh (Row Level Security / RLS)**:
  - Saklar berbagi lokasi (On/Off) kapan saja.
  - Data koordinat hanya bisa diakses oleh akun keluarga yang terhubung.
  - Fitur tambah keluarga via email dan fitur **Hapus Teman / Putus Hubungan**.
- ⏰ **Supabase Keep-Alive Otomatis (GitHub Actions)**: Workflow otomatis mem-ping database Supabase via REST API setiap 3 hari agar project gratis tidak pernah di-*pause*.

---

## 🛠️ Tech Stack

### Mobile App (`apps/mobile`)
- **Framework**: [Flutter](https://flutter.dev/) (Dart v3.5+)
- **Backend-as-a-Service**: [Supabase Flutter SDK](https://pub.dev/packages/supabase_flutter) (`supabase_flutter`)
- **Map & Geolocation**: `flutter_map`, `latlong2`, `geolocator`
- **Map Tiles**: Google Maps Road, Satellite Hybrid, & Terrain Tiles + Carto Dark Matter
- **Navigation & External Intent**: `url_launcher`
- **Background Tracking**: Android Foreground Service + WakeLock, `workmanager`, `battery_plus`
- **Database & Realtime**: PostgreSQL + PostGIS di Supabase Cloud (Tabel: `profiles`, `user_locations`, `friendships`, `sos_alerts`, `places`, `location_history`, `quick_checkins`)

---

## 📁 Struktur Direktori

```text
FamLocation/
├── .agents/                    # Panduan Agent (Stack & Design Skills)
│   └── skills/
│       ├── famloc-stack/SKILL.md
│       └── famloc-design/SKILL.md
├── .github/
│   └── workflows/
│       └── supabase-keep-alive.yml # GitHub Actions Supabase Keep-Alive Cron
├── apps/
│   └── mobile/                 # Aplikasi Flutter Mobile
│       ├── android/            # Android Manifest & Native Service Config
│       ├── lib/
│       │   ├── screens/
│       │   │   ├── auth_screen.dart     # Login & Register Supabase
│       │   │   ├── map_home.dart        # Layar Peta Utama, SOS, Geofencing, Trail, & Kabar Kilat
│       │   │   ├── family_screen.dart   # Manajemen Anggota Keluarga & Hapus Teman
│       │   │   ├── profile_screen.dart  # Edit Nama, Ganti Password, Upload Avatar
│       │   │   └── onboarding_screen.dart
│       │   ├── supabase_service.dart    # Layanan Auth, Database, Storage, SOS, Places, & WebSocket
│       │   ├── background_task.dart     # Background Fallback Task (Workmanager)
│       │   ├── theme.dart               # Design System & UI Tokens
│       │   └── main.dart                # Entrypoint Flutter
│       └── pubspec.yaml
├── docs/
│   └── PRD.md                  # Product Requirements Document
├── supabase/
│   └── migrations/
│       └── 20260831_init.sql   # Skema PostgreSQL (PostGIS, RLS, Realtime, Storage)
└── README.md
```

---

## 🚀 Panduan Menjalankan Aplikasi

### 1. Menjalankan di Emulator / HP Fisik

1. Masuk ke direktori `apps/mobile`:
   ```bash
   cd apps/mobile
   flutter pub get
   ```

2. Jalankan aplikasi:
   ```bash
   flutter run
   ```

3. **Build File APK Release**:
   ```bash
   flutter build apk --release
   ```
   *File APK siap pasang akan tersedia di: `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`*.

---

## 📄 Lisensi & Atribusi

- **Data & Gambar Peta**: [© Google Maps](https://www.google.com/maps) / [© OpenStreetMap](https://www.openstreetmap.org)
- **Infrastruktur Backend & Realtime**: [Supabase](https://supabase.com/)
