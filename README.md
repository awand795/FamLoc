# 📍 FamLoc — Family Live Location Tracker (Supabase Realtime)

**FamLoc** adalah aplikasi pelacak lokasi keluarga (khusus pengguna dan keluarga tercinta) secara *realtime*, privat, hemat daya, dan bebas biaya server. Dibangun langsung menggunakan **Flutter** dan **Supabase Realtime (WebSocket)** tanpa perlu mengelola server backend terpisah.

---

## ✨ Fitur Utama

- 🚀 **Realtime Live Tracking (WebSocket)**: Pergerakan lokasi anggota keluarga di peta disiarkan secara instan (<100ms latency) melalui koneksi WebSocket persisten bawaan Supabase (`supabase_flutter`).
- 🔋 **Indikator Baterai & Status Gerak**: Menampilkan persentase baterai HP keluarga secara akurat serta deteksi otomatis apakah sedang diam atau bergerak.
- 🔒 **Privasi & Keamanan Keluarga Penuh**:
  - **Saklar Berbagi (On/Off)**: Kendali penuh kapan ingin membagikan lokasi atau mematikannya.
  - **Row Level Security (RLS)**: Data lokasi dan profil dilindungi di tingkat PostgreSQL.
- 🛡️ **Deteksi Fake GPS**: Peringatan jika lokasi yang dikirim terindikasi berasal dari aplikasi *mock location*.
- 🗺️ **Peta Open-Source Tanpa Biaya API Key**: Menggunakan `flutter_map` dengan layer OpenStreetMap (OSM).
- ☁️ **100% Serverless (BaaS)**: Menggunakan Supabase untuk Database PostGIS, Auth, Storage Avatar, dan Realtime WebSocket. Bebas masalah *sleep* / *cold start* server.

---

## 🛠️ Tech Stack

### Mobile App (`apps/mobile`)
- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **Backend-as-a-Service**: [Supabase Flutter SDK](https://pub.dev/packages/supabase_flutter) (`supabase_flutter`)
- **Map & Geolocation**: `flutter_map`, `latlong2`, `geolocator`
- **Background Sharing**: `workmanager`, `battery_plus`
- **Database & Realtime**: PostgreSQL + PostGIS di Supabase

---

## 📁 Struktur Direktori

```text
FamLocation/
├── .agents/                    # Konfigurasi skill & arsitektur
├── apps/
│   └── mobile/                 # Aplikasi Flutter (Mobile)
│       ├── lib/
│       │   ├── screens/        # UI Screens (Map, Profile, Auth, Onboarding)
│       │   ├── supabase_service.dart # Layanan Auth, Storage & Realtime Live Location
│       │   ├── background_task.dart  # Background periodic sharing (Workmanager)
│       │   ├── theme.dart      # Design System & Colors
│       │   └── main.dart       # Entrypoint Flutter
│       └── pubspec.yaml
├── supabase/
│   └── migrations/
│       └── 20260831_init.sql   # Skema Database Supabase PostGIS + RLS + Storage
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

3. **Login / Daftar Akun**:
   - Daftarkan akun pertama untuk Anda (misal `anda@gmail.com`).
   - Daftarkan akun kedua untuk Mama Anda di HP-nya (misal `mama@gmail.com`).
   - Begitu kedua akun masuk, kedua HP akan langsung saling membagikan dan melihat pergerakan lokasi di peta secara realtime!

---

## 📄 Lisensi & Atribusi

- **Data Peta**: [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright)
- **Infrastruktur Realtime**: [Supabase](https://supabase.com/)
