# 📍 FamLoc — Family Live Location Tracker (Supabase Realtime)

**FamLoc** adalah aplikasi pelacak lokasi keluarga (khusus Anda dan keluarga tercinta) secara *realtime*, privat, hemat daya, dan bebas biaya server. Dibangun langsung menggunakan **Flutter** dan **Supabase Realtime (WebSocket)** tanpa perlu mengelola server backend terpisah.

---

## ✨ Fitur Utama

- 🚀 **Realtime Live Tracking (WebSocket)**: Pergerakan lokasi anggota keluarga di peta disiarkan secara instan (<100ms latency) melalui koneksi WebSocket persisten bawaan Supabase (`supabase_flutter`).
- 🗺️ **Tampilan Peta Google Maps Asli & Layer Switcher**:
  - **Mode Default**: Peta Jalan Google Maps yang bersih, rapi, dan modern.
  - **Mode Satelit**: Foto Udara Satelit Nyata Google Maps (dengan label nama jalan).
  - **Mode Terrain**: Peta Kontur Topografi Ketinggian Tanah.
- 🎥 **Auto-Follow Kamera Realtime**: Kamera peta otomatis meluncur dan mengikuti pergerakan Mama/keluarga di jalan secara langsung saat difokuskan.
- 🧭 **Petunjuk Arah 1-Ketukan (Buka Google Maps)**: Tombol *"Rute Maps"* yang langsung membuka aplikasi Google Maps di HP dengan rute navigasi tercepat dan estimasi waktu sampai (ETA).
- 🚨 **Sinyal Darurat SOS Realtime**: Tombol darurat SOS merah yang seketika menyiarkan peringatan darurat ke seluruh anggota keluarga dengan koordinat presisi dan tombol respon cepat.
- 🚗 **Speedometer & Status Gerak Cerdas**: Mendeteksi otomatis apakah keluarga sedang *Berkendara (km/jam)*, *Berjalan Kaki*, atau *Berhenti/Diam*.
- 🔋 **Live Battery Badge di Peta**: Persentase sisa baterai HP keluarga tampil langsung di atas marker nama di peta (`Mama 🔋 85%`) dengan indikator warna merah saat $\le 20\%$.
- 👥 **Menu Pemilih Anggota Keluarga**: Ketuk tombol keluarga bulat di kanan bawah untuk memilih anggota keluarga yang ingin dipantau dengan status online, baterai, dan jarak tempuh.
- 🔒 **Pelacakan Latar Belakang Penuh (Android 14+ & Screen-Off WakeLock)**:
  - Lokasi tetap terkirim secara realtime saat HP di dalam kantong celana atau saat layar HP dimatikan/terkunci di perjalanan.
  - Dilengkapi *Foreground Service* dengan notifikasi status bar dan dukungan sistem Android 10, 11, 12, 13, 14, hingga 15.
- 🛡️ **Privasi & Keamanan Penuh (Row Level Security / RLS)**:
  - Saklar berbagi lokasi (On/Off) kapan saja.
  - Data koordinat hanya bisa diakses oleh akun keluarga yang terhubung.
  - Fitur tambah keluarga via email dan fitur **Hapus Teman / Putus Hubungan**.
  - Deteksi *Mock Location / Fake GPS*.
- ⏰ **Supabase Keep-Alive Otomatis (GitHub Actions)**: Workflow otomatis mem-ping database Supabase via REST API setiap 3 hari agar project gratis tidak pernah di-*pause*.

---

## 🛠️ Tech Stack

### Mobile App (`apps/mobile`)
- **Framework**: [Flutter](https://flutter.dev/) (Dart v3.5+)
- **Backend-as-a-Service**: [Supabase Flutter SDK](https://pub.dev/packages/supabase_flutter) (`supabase_flutter`)
- **Map & Geolocation**: `flutter_map`, `latlong2`, `geolocator`
- **Map Tiles**: Google Maps Road, Satellite Hybrid, & Terrain Tiles (`mt0-mt3.google.com`)
- **Navigation & External Intent**: `url_launcher`
- **Background Tracking**: Android Foreground Service + WakeLock, `workmanager`, `battery_plus`
- **Database & Realtime**: PostgreSQL + PostGIS di Supabase Cloud

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
│       │   │   ├── map_home.dart        # Layar Peta Utama, SOS, Layer Switcher, & Auto-Follow
│       │   │   ├── family_screen.dart   # Manajemen Anggota Keluarga & Hapus Teman
│       │   │   ├── profile_screen.dart  # Edit Nama, Ganti Password, Upload Avatar
│       │   │   └── onboarding_screen.dart
│       │   ├── supabase_service.dart    # Layanan Auth, Database, Storage, SOS, & WebSocket
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

### 1. Prasyarat
- **Flutter SDK**: v3.5 atau lebih baru
- Akun / Project di [Supabase](https://supabase.com/)

---

### 2. Menjalankan di Emulator / HP Fisik

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

- **Data & Gambar Peta**: [© Google Maps](https://www.google.com/maps)
- **Infrastruktur Backend & Realtime**: [Supabase](https://supabase.com/)
