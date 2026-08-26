---
name: famloc-stack
description: Tech stack dan arsitektur aplikasi FamLoc (live location antar teman/keluarga). Gunakan skill ini saat menulis kode backend, mengatur database, deploy, atau memutuskan hal teknis apa pun di project ini agar konsisten dengan keputusan yang sudah dikunci.
---

# Skill: FamLoc — Stack & Arsitektur

## Keputusan Terkunci (JANGAN diubah tanpa diskusi ulang)

| Komponen | Pilihan | Catatan |
|---|---|---|
| Mobile app | **Flutter (Dart)** | Satu codebase Android + iOS |
| Backend | **Node.js + Express** | Dijalankan sebagai serverless functions |
| Hosting backend | **Vercel** (free tier) | Serverless — TIDAK support WebSocket/long-running process |
| Database | **Aiven PostgreSQL + ekstensi PostGIS** | Sudah dimiliki user; koneksi via connection string env var |
| Realtime MVP | **Polling adaptif** | Foreground/map aktif = tiap 10 dtk; background = 30–60 dtk. TANPA WebSocket di MVP |
| Notifikasi MVP | **In-app saja** (badge/list) | Push notification (FCM/APNs) = fase 2 — jangan setup FCM di MVP |
| Avatar | **Aiven Postgres** (`user_avatars.bytea`) | Client resize ≤256px JPEG <100KB sebelum upload; serve via API + Cache-Control; tanpa storage pihak ketiga |
| Reverse geocoding | **Nominatim OSM** + tabel `geocode_cache` | Maks 1 req/dtk; bulatkan koordinat ~4 desimal sebagai cache key |
| Link undangan | Landing page statis di Vercel | Tampilkan nama pengundang + `invite_code` + tombol buka app; TANPA deep link native di MVP |
| Sesi | **Multi-device diperbolehkan** | JWT sampai expired; tidak ada invalidasi lintas perangkat di MVP |
| Crash reporting | **Sentry free tier** | Pasang SDK sentry_flutter saat scaffold mobile |
| Auth | **Email + password** (bcrypt hash di server, token JWT). Tanpa OTP/sms tanpa layanan email di MVP — biaya Rp0. Verifikasi email = fase 2. **KEPUTUSAN USER: email transaksional dikirim via SMTP Gmail pribadi** (nodemailer). Simpan kredensial di env var (`SMTP_USER`, `SMTP_PASS`), JANGAN commit |
| Map SDK | **flutter_map + tile OpenStreetMap** | Gratis, tanpa API key. WAJIB sertakan atribusi © OpenStreetMap contributors. Jangan tambah google_maps_flutter/mapbox di MVP |

## Aturan Arsitektur

1. **Flutter TIDAK PERNAH akses database langsung.** Semua lewat REST API Express.
2. **Tidak ada WebSocket di MVP.** Jangan tambahkan `ws`/`socket.io`. Realtime = Flutter poll `GET /api/v1/friends/locations`.
3. **Serverless-safe code**: jangan simpan state in-memory antar request (tiap function invocation bisa beda container). Semua state di Postgres.
4. **Koneksi DB**: pakai pool dengan limit kecil (mis. `max: 5`) karena Vercel membuka banyak instance; pertimbangkan pooling (PgBouncer/Aiven pooled connection string).
5. **Keamanan lokasi**: endpoint lokasi WAJIB verifikasi pertemanan mutual sebelum mengembalikan data. Unfriend/block = langsung hilang akses.
6. **Semua komunikasi HTTPS** (default di Vercel).

## Kontrak API (v1)

```
POST   /api/v1/auth/register        { name, email, password } → { token, user }
POST   /api/v1/auth/login           { email, password } → { token, user }
GET    /api/v1/me                   profil sendiri (auth)PATCH  /api/v1/me/sharing       { sharing_on: boolean }
PATCH  /api/v1/me/precision     { mode: 'exact'|'approx' } — approx: server fuzz ±500m
                                  saat SERVE ke teman (posisi asli tetap tersimpan;
                                  pemilik selalu lihat akurat)
PATCH  /api/v1/me/password      { old_password, new_password }

POST   /api/v1/friends/request      { target_user_id } → kirim permintaan
POST   /api/v1/friends/respond      { request_id, action: accept|reject }
GET    /api/v1/friends              daftar teman mutual + status
DELETE /api/v1/friends/:id          unfriend
GET    /api/v1/friend-requests      incoming/outgoing requestsPOST   /api/v1/locations            { lat, lng, accuracy, heading, battery } (auth + sharing ON)
GET   /api/v1/friends/locations    → posisi terakhir semua teman yang sharing ON
                                      HANYA teman mutual; termasuk battery & updated_at
                                      untuk status bergerak/diam (turunan speed/heading) & baterai
PUT    /api/v1/me/avatar            body: image/jpeg base64 (client resize ≤256px, <100KB)
GET    /api/v1/users/:id/avatar     → serve bytea + Cache-Control immutable (avatar_url = versi/timestamp)
POST   /api/v1/locations            { lat, lng, accuracy, heading, battery,
                                      is_mocked } (auth + sharing ON)
PATCH  /api/v1/me/schedule          { days:[0-6], start:'06:30', end:'15:00',
                                      enabled:boolean } | null = hapus jadwal
POST   /api/v1/friends/:id/location-request   minta teman nyalakan sharing
POST   /api/v1/location-requests/:rid         { action: 'accept'|'dismiss' }
GET    /api/v1/notifications          notifikasi in-app: friend requests,
                                      location requests, dsb.
```

## Skema Database (PostgreSQL + PostGIS)

```sql
CREATE EXTENSION IF NOT EXISTS postgis;

users (
  id            UUID PK DEFAULT gen_random_uuid(),
  email         VARCHAR UNIQUE NOT NULL,
  password_hash VARCHAR NOT NULL,
  name          VARCHAR NOT NULL,
  invite_code   VARCHAR UNIQUE NOT NULL,       -- untuk QR/link undangan
  avatar_version INTEGER DEFAULT 0,             -- cache-buster URL avatar
  sharing_on    BOOLEAN DEFAULT FALSE,
  location_precision VARCHAR DEFAULT 'exact' CHECK (location_precision IN ('exact','approx')),
  sharing_on    BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT now()
)

user_avatars (
  user_id   UUID PK REFERENCES users(id),
  image     BYTEA NOT NULL CHECK (octet_length(image) <= 102400), -- max 100KB
  updated_at TIMESTAMPTZ DEFAULT now()
)

geocode_cache (
  lat_lng_key VARCHAR PK,   -- 'lat,lng' dibulatkan ~4 desimal (~11m)
  address     TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
)

friend_requests (
  id          UUID PK,
  requester_id UUID REFERENCES users(id),
  addressee_id UUID REFERENCES users(id),
  status      VARCHAR CHECK (status IN ('pending','accepted','rejected')),
  created_at  TIMESTAMPTZ,
  UNIQUE (requester_id, addressee_id)
)

-- teman mutual diturunkan dari friend_requests status='accepted' dua arah,
-- atau simpan tabel friendships denormalized untuk query cepat:
friendships ( user_id_a UUID, user_id_b UUID, created_at TIMESTAMPTZ,
              CHECK (user_id_a < user_id_b), PRIMARY KEY (user_id_a, user_id_b) )

user_locations (
  user_id   UUID PK REFERENCES users(id),   -- posisi TERAKHIR saja (MVP)
  geom      GEOGRAPHY(POINT, 4326) NOT NULL,
  accuracy  REAL,
  heading   REAL,
  battery   SMALLINT CHECK (battery BETWEEN 0 AND 100), -- level baterai %
  is_mocked BOOLEAN DEFAULT FALSE,                      -- deteksi fake GPS
  updated_at TIMESTAMPTZ DEFAULT now()
)

sharing_schedules (
  user_id UUID PK REFERENCES users(id),
  days    SMALLINT[] NOT NULL,        -- 0=Minggu .. 6=Sabtu
  start_time TIME NOT NULL,
  end_time   TIME NOT NULL,
  enabled BOOLEAN DEFAULT TRUE,
  -- dieksekusi oleh CLIENT (Workmanager/AlarmManager); server hanya menyimpan
)

location_requests (
  id           UUID PK DEFAULT gen_random_uuid(),
  requester_id UUID REFERENCES users(id),   -- yang meminta
  target_id    UUID REFERENCES users(id),   -- diminta nyalakan sharing
  status       VARCHAR CHECK (status IN ('pending','accepted','dismissed')),
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE (requester_id, target_id, status)   -- cegah spam: max 1 pending/target
)
CREATE INDEX idx_user_locations_geom ON user_locations USING GIST (geom);
```

## Deploy ke Vercel

- Struktur repo: monorepo `apps/mobile` (Flutter) + `apps/api` (Express).

### Email SMTP (fase 2)
Konfigurasi Gmail SMTP milik user (dipindah dari project Laravel lain):
- Host: `smtp.gmail.com` · Port: `465` · Secure: `true` (SMTPS)
- User: dari env var `SMTP_USER` · Password: **App Password** dari env var `SMTP_PASS`
- Pakai library `nodemailer`; contoh transport:
```js
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: 465,
  secure: true,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
});
```
- Batasan: limit ±500 email/hari, header `From` ditulis ulang ke alamat Gmail pengirim.
- ⚠️ App Password pernah terekspos di chat — user disarankan regenerate sebelum production.
- API: gunakan pola serverless (`vercel.json` rewrite `/api/(.*)` → handler, atau Vercel Functions per-route).
- Env vars di Vercel: `DATABASE_URL`, `JWT_SECRET`, `OTP_PROVIDER_KEY`, dst. JANGAN commit `.env`.
- Free tier: hati-hati kuota function invocations — interval polling background jangan lebih agresif dari 30 dtk.

## Upgrade Path Fase 2 (jangan dikerjakan sekarang)

- WebSocket realtime: tempel **Ably/Pusher free tier** (publish dari Express setelah validasi friendship; Flutter subscribe via `ably_flutter`/`pusher_channels_flutter`). Backend polling tidak perlu dibuang.
- Geofence alert: cron/Vercel Cron + query radius PostGIS (`ST_DWithin`).
