# PRD — FamLoc (Aplikasi Live Location Keluarga)

> **Nama Produk:** "FamLoc"  
> **Versi:** 1.0 (Produksi / Serverless Supabase Realtime)  
> **Tanggal:** 1 September 2026  
> **Status:** Selesai & Terverifikasi  

---

## 1. Ringkasan Produk

**FamLoc** adalah aplikasi mobile pelacak lokasi keluarga secara *realtime* (live duplex), privat, dan bebas biaya server. Aplikasi ini dirancang khusus untuk memantau keselamatan dan keberadaan anggota keluarga (misalnya saling memantau antara Anda dan orang tua tercinta) saat sedang dalam perjalanan atau beraktivitas di luar rumah.

---

## 2. Masalah & Solusi

| Masalah | Solusi di FamLoc |
|---|---|
| Orang tua/anak cemas saat anggota keluarga berada di perjalanan | Pelacakan live terus-menerus (<100ms) di peta dengan kecepatan & baterai |
| Bertanya berulang kali *"Sudah sampai mana?"* saat di jalan | Cukup buka aplikasi, posisi langsung terlihat secara realtime |
| Menjemput keluarga di lokasi yang tidak familiar | Tombol **"Rute Maps"** satu ketukan langsung membuka rute Google Maps Navigasi |
| Terjadi kendala darurat di jalan (ban bocor, mogok) | Tombol **SOS Darurat** seketika menyiarkan peringatan darurat ke seluruh HP keluarga |
| Aplikasi pelacak lain boros baterai atau dimatikan oleh HP | Menggunakan *Android Foreground Service + WakeLock* yang tetap aktif di layar mati |

---

## 3. Fitur Utama

### 3.1 Live Tracking & Peta
* **Google Maps Road, Satellite Hybrid, & Terrain Layer Switcher**: Tampilan peta jalan, foto udara satelit nyata, dan topografi dengan ubin Google Maps super cepat via CDN.
* **Auto-Follow Kamera Realtime**: Kamera peta otomatis meluncur dan mengikuti pergerakan keluarga yang sedang dipantau.
* **Speedometer & Status Gerak**: Mendeteksi kecepatan berkendara (km/jam), berjalan kaki, atau diam.
* **Indikator Baterai**: Menampilkan sisa persentase baterai di marker peta (`🔋 85%`) dengan warna merah saat $\le 20\%$.
* **Perhitungan Jarak**: Menghitung jarak presisi antara Anda dan anggota keluarga secara realtime (misal: `2.4 km dari kamu`).

### 3.2 Keamanan & Darurat
* **Sinyal Darurat SOS**: Tombol SOS yang memunculkan banner darurat di HP keluarga dengan opsi navigasi kilat dan tombol hubungi.
* **Deteksi Fake GPS**: Mendeteksi status `is_mocked` dari hardware GPS.
* **Privasi Penuh (Sharing Toggle)**: Saklar on/off untuk berhenti membagikan posisi kapan saja.

### 3.3 Manajemen Keluarga
* **Tambah Anggota**: Tambah keluarga cukup dengan memasukkan email akunnya.
* **Pemilih Anggota Keluarga**: Menu bottom sheet untuk memilih siapa yang ingin dipantau.
* **Hapus Teman**: Memutus koneksi pertemanan dengan 1 ketukan + konfirmasi.

### 3.4 Pelacakan Latar Belakang (Background Service)
* **Android 14+ FGS & WakeLock**: Lokasi tetap terkirim saat HP di kantong celana dan layar dimatikan.
* **Supabase Keep-Alive Cron**: GitHub Actions workflow yang mem-ping database tiap 3 hari agar Supabase project tidak pernah mengalami jeda auto-pause.

---

## 4. Arsitektur Teknis

```
[ Flutter Mobile App (Android/iOS) ]
       │              ▲
       │ HTTPS / REST │ WSS (WebSocket CDC)
       ▼              │
[ Supabase PostgreSQL + PostGIS ]
   ├── profiles
   ├── user_locations
   ├── friendships
   ├── sos_alerts
   └── storage.buckets ('avatars')
```

| Komponen | Teknologi |
|---|---|
| Framework Mobile | **Flutter (Dart v3.5+)** |
| BaaS & Database | **Supabase (PostgreSQL 15 + PostGIS)** |
| Protokol Realtime | **Supabase Realtime (WebSocket Postgres Changes)** |
| Peta & Tile | **`flutter_map` + Google Maps Tile Engine (`mt0-mt3`)** |
| Navigasi Eksternal | **`url_launcher` (Google Maps Navigation Intent)** |
| Sensor & Hardware | **`geolocator` (FGS + WakeLock), `battery_plus`** |
| Keep-Alive System | **GitHub Actions Scheduled Cron (Setiap 3 Hari)** |
