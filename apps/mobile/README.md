# 📱 FamLoc Mobile App (Flutter)

Aplikasi mobile FamLoc dibangun dengan **Flutter** dan terhubung langsung ke **Supabase** secara *serverless* menggunakan **PostgreSQL PostGIS**, **Supabase Auth**, **Supabase Storage**, dan **Supabase Realtime (WebSocket)**.

---

## 🚀 Perintah Cepat

### 1. Install Dependensi
```bash
flutter pub get
```

### 2. Jalankan di Emulator / Device
```bash
flutter run
```

### 3. Build APK Release
```bash
flutter build apk --release
```
Lokasi APK hasil build:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📦 Struktur `lib/`

* `screens/`
  * `map_home.dart`: Peta utama, auto-follow camera, layer switcher (Google Road/Satellite/Terrain), SOS alert system, dan live speedometer.
  * `family_screen.dart`: Manajemen anggota keluarga (tambah via email, lacak langsung di peta, dan hapus teman).
  * `profile_screen.dart`: Profil pengguna, edit nama, upload avatar ke Supabase Storage, ganti password, dan logout.
  * `auth_screen.dart`: Pendaftaran & login akun Supabase (auto-confirm aktif).
  * `onboarding_screen.dart`: Layar pengenalan awal saat aplikasi pertama kali dipasang.
* `supabase_service.dart`: Layanan penghubung ke database Supabase, stream realtime WebSocket, upload storage, dan broadcast SOS.
* `background_task.dart`: Layanan background fallback via Workmanager.
* `theme.dart`: Design system (warna, tipografi Plus Jakarta Sans, gradient, dan radius).
* `main.dart`: Entrypoint aplikasi & inisialisasi Supabase.
