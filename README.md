# 📍 FamLoc — Family & Friend Live Location Tracker

**FamLoc** adalah aplikasi pelacak lokasi keluarga dan teman secara *realtime*, privat, dan hemat daya. Dibangun dengan arsitektur modern **WebSocket duplex**, **Flutter**, **Node.js (Express)**, dan basis data spasial **PostgreSQL + PostGIS**.

---

## ✨ Fitur Utama

- 🚀 **Realtime Live Tracking (WebSocket)**: Pergerakan lokasi teman dan keluarga disiarkan secara instan (<100ms latency) melalui koneksi WebSocket persisten (`wss://`).
- 🔒 **Kontrol Privasi Penuh**:
  - **Saklar Berbagi (On/Off)**: Pengguna memegang kendali penuh kapan ingin membagikan atau mematikan lokasi.
  - **Mode Presisi (Akurat vs Kasar $\pm$500m)**: Lokasi disamarkan di level server sebelum dikirim ke teman jika memilih mode *approx*.
  - **Hanya Teman Mutual**: Lokasi hanya dapat dilihat oleh teman yang saling menerima permintaan pertemanan.
- 🔋 **Indikator Baterai & Status Gerak**: Menampilkan persentase baterai perangkat teman serta status apakah sedang diam atau bergerak.
- 🛡️ **Deteksi Fake GPS (Anti Mock Location)**: Peringatan jika lokasi yang dikirim terindikasi berasal dari aplikasi *mock location*.
- 🗺️ **Peta Open-Source Tanpa Biaya API Key**: Menggunakan `flutter_map` dengan layer ubin OpenStreetMap (OSM) dan *reverse geocoding* alamat cerdas dengan sistem *caching*.
- ⏰ **24/7 Zero Cold-Start Keep-Alive**: Dilengkapi workflow otomatis GitHub Actions Cron untuk menjaga service Render tetap aktif tanpa mengalami *sleep* / *cold start*.
- 👨‍👩‍👧 **Undangan Cepat**: Menggunakan kode unik 8 karakter atau pemindaian QR Code untuk menambah teman dengan mudah.

---

## 🛠️ Tech Stack

### Mobile App (`apps/mobile`)
- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **Map & Geolocation**: `flutter_map`, `latlong2`, `geolocator`
- **Realtime Networking**: `web_socket_channel`, `http`
- **Background Sharing**: `workmanager`, `battery_plus`
- **Scanner & QR**: `mobile_scanner`, `qr_flutter`

### Backend API & Realtime Server (`apps/api`)
- **Runtime**: [Node.js](https://nodejs.org/) (Express)
- **Realtime Engine**: [ws](https://github.com/websockets/ws) (WebSocket Server)
- **Database**: [Aiven PostgreSQL](https://aiven.io/) dengan ekstensi **PostGIS**
- **Autentikasi**: JWT (JSON Web Token) & bcryptjs
- **Reverse Geocoding**: Nominatim OpenStreetMap API + Cache Database

### DevOps & Hosting
- **Hosting Backend**: [Render](https://render.com/) (Web Service)
- **Keep-Alive Automation**: GitHub Actions (Scheduled Cron)

---

## 📁 Struktur Direktori

```text
FamLocation/
├── .agents/                    # Konfigurasi skill & aturan arsitektur
├── .github/
│   └── workflows/
│       └── keep-alive.yml      # Cron GitHub Actions ping backend Render tiap 10 mnt
├── apps/
│   ├── api/                    # Backend Node.js Express + WebSocket
│   │   ├── migrations/         # SQL Migration (PostGIS schema)
│   │   ├── src/
│   │   │   ├── routes/         # REST API routes (auth, me, friends, locations, misc)
│   │   │   ├── auth.js         # JWT & privacy fuzzing
│   │   │   ├── db.js           # PostgreSQL connection pool
│   │   │   ├── websocket.js    # WebSocket server & broadcast logic
│   │   │   ├── app.js          # Express app
│   │   │   └── server.js       # Entrypoint HTTP + WS Server
│   │   └── package.json
│   └── mobile/                 # Flutter Mobile Application
│       ├── lib/
│       │   ├── screens/        # UI Screens (Map, Friends, Notifications, Profile, Auth)
│       │   ├── api_client.dart # HTTP REST Client
│       │   ├── realtime_service.dart # WebSocket Client & Auto-reconnect
│       │   ├── theme.dart      # Design System & Colors
│       │   └── main.dart       # Entrypoint Flutter
│       └── pubspec.yaml
├── render.yaml                 # Blueprint deployment Render
└── README.md
```

---

## 🚀 Panduan Memulai (Local Development)

### 1. Prasyarat
- **Node.js**: v20 atau lebih baru
- **Flutter SDK**: v3.5 atau lebih baru
- **PostgreSQL**: Dengan ekstensi PostGIS aktif (misal Aiven / PostgreSQL lokal)

---

### 2. Menjalankan Backend (`apps/api`)

1. Masuk ke direktori backend dan instal dependensi:
   ```bash
   cd apps/api
   npm install
   ```

2. Buat file konfigurasi `.env.local`:
   ```env
   PORT=3000
   DATABASE_URL=postgres://user:password@host:port/dbname?sslmode=require
   JWT_SECRET=super-secret-jwt-key
   SMTP_HOST=smtp.gmail.com
   SMTP_USER=your-email@gmail.com
   SMTP_PASS=your-gmail-app-password
   ```

3. Jalankan migrasi database:
   ```bash
   npm run migrate
   ```

4. Jalankan server lokal:
   ```bash
   npm run dev
   ```
   Server akan aktif di `http://localhost:3000` dan WebSocket di `ws://localhost:3000/ws`.

---

### 3. Menjalankan Aplikasi Mobile (`apps/mobile`)

1. Masuk ke direktori mobile:
   ```bash
   cd apps/mobile
   flutter pub get
   ```

2. *(Opsional saat testing di HP fisik / Emulator)*:
   Sesuaikan `kApiBase` di [`apps/mobile/lib/api_client.dart`](file:///D:/app%20android/FamLocation/apps/mobile/lib/api_client.dart):
   - **Emulator Android**: `http://10.0.2.2:3000/api/v1`
   - **HP Fisik (USB Debugging)**: Jalankan `adb reverse tcp:3000 tcp:3000` lalu gunakan `http://127.0.0.1:3000/api/v1`
   - **Production (Render)**: `https://famloc-api.onrender.com/api/v1`

3. Jalankan aplikasi:
   ```bash
   flutter run
   ```

---

## ☁️ Panduan Deploy ke Render

1. Buat akun di [Render](https://render.com/).
2. Buat **New Web Service** dan hubungkan repositori GitHub ini.
3. Konfigurasikan Web Service:
   - **Root Directory**: `apps/api`
   - **Runtime**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
4. Tambahkan Environment Variables di dashboard Render:
   - `DATABASE_URL` : URL koneksi PostgreSQL PostGIS (misal dari Aiven)
   - `JWT_SECRET` : String rahasia JWT
   - `SMTP_USER` & `SMTP_PASS` : Kredensial email SMTP
5. Simpan dan deploy. Render akan memberikan URL seperti `https://famloc-api.onrender.com`.

---

## ⚡ Setup Keep-Alive 24/7 (Cegah Cold-Start)

Agar backend Render Free Tier tidak tidur setelah 15 menit idle:
1. Buka Repositori GitHub Anda.
2. Masuk ke **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions**.
3. Tambahkan secret baru:
   - **Name**: `RENDER_BACKEND_URL`
   - **Value**: `https://famloc-api.onrender.com` (ganti dengan URL Render Anda)
4. Workflow [`.github/workflows/keep-alive.yml`](file:///D:/app%20android/FamLocation/.github/workflows/keep-alive.yml) akan otomatis mem-ping server setiap 10 menit.

---

## 📄 Lisensi & Atribusi

- **Data Peta**: [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright)
- **Geocoding**: [Nominatim OpenStreetMap](https://nominatim.org/)
