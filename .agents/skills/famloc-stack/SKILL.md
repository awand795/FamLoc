---
name: famloc-stack
description: Tech stack dan arsitektur aplikasi FamLoc (live location keluarga). Gunakan skill ini saat menulis kode, mengatur database, deploy, atau memutuskan hal teknis apa pun di project ini agar konsisten dengan keputusan yang sudah dikunci.
---

# Skill: FamLoc — Stack & Arsitektur (Supabase Realtime)

## Keputusan Terkunci

| Komponen | Pilihan | Catatan |
|---|---|---|
| Mobile App | **Flutter (Dart v3.5+)** | Satu codebase Android + iOS |
| Backend & Database | **Supabase (BaaS)** | 100% Serverless. Mengelola Database PostgreSQL + PostGIS, Auth, Storage, dan Realtime WebSocket |
| Realtime Live Tracking | **Supabase Realtime (WebSocket)** | Menggunakan Postgres Changes stream duplex via `supabase_flutter` |
| Auth | **Supabase Auth** | Email + Password bawaan Supabase, auto-confirm aktif, sesi persisten |
| Storage Avatar | **Supabase Storage** | Bucket `avatars` publik untuk foto profil pengguna |
| Peta & Tile Engine | **`flutter_map` + Multi-Layer Engine** | Google Maps Jalan (`lyrs=m`), Satelit Hybrid (`lyrs=y`), Terrain (`lyrs=p`), dan Carto Dark Matter |
| Geofencing & History | **Supabase Realtime (`places`, `location_history`)** | Lingkaran zona aman transparan dan polyline rute hari ini |
| Komunikasi Cepat | **Supabase Realtime (`quick_checkins`)** | Siaran kabar kilat 1-ketukan antar keluarga |
| Navigasi Eksternal | **`url_launcher`** | Intent langsung ke Google Maps Navigasi (`google.navigation` / URL directions) |
| Pelacakan Latar Belakang | **Android Foreground Service + WakeLock** | Izin `ACCESS_BACKGROUND_LOCATION`, `POST_NOTIFICATIONS`, dan deklarasi `foregroundServiceType="location"` di AndroidManifest.xml |
| Keep-Alive System | **GitHub Actions** | Ping REST API setiap 3 hari untuk mencegah auto-pause pada Supabase Free Tier |

## Skema Database Supabase

1. **`public.profiles`**: `id (UUID PK)`, `name (TEXT)`, `email (TEXT)`, `avatar_url (TEXT)`, `sharing_on (BOOLEAN)`
2. **`public.user_locations`**: `user_id (UUID PK)`, `lat (DOUBLE)`, `lng (DOUBLE)`, `accuracy (REAL)`, `heading (REAL)`, `speed (DOUBLE)`, `battery (SMALLINT)`, `is_mocked (BOOLEAN)`, `updated_at (TIMESTAMPTZ)`
3. **`public.friendships`**: `id (UUID PK)`, `user_id_a (UUID)`, `user_id_b (UUID)`, `created_at (TIMESTAMPTZ)`
4. **`public.sos_alerts`**: `id (UUID PK)`, `user_id (UUID)`, `lat (DOUBLE)`, `lng (DOUBLE)`, `battery (SMALLINT)`, `is_active (BOOLEAN)`, `created_at (TIMESTAMPTZ)`
5. **`public.places`**: `id (UUID PK)`, `user_id (UUID)`, `name (TEXT)`, `icon (TEXT)`, `lat (DOUBLE)`, `lng (DOUBLE)`, `radius (DOUBLE)`, `created_at (TIMESTAMPTZ)`
6. **`public.location_history`**: `id (UUID PK)`, `user_id (UUID)`, `lat (DOUBLE)`, `lng (DOUBLE)`, `speed (DOUBLE)`, `created_at (TIMESTAMPTZ)`
7. **`public.quick_checkins`**: `id (UUID PK)`, `user_id (UUID)`, `message (TEXT)`, `icon (TEXT)`, `lat (DOUBLE)`, `lng (DOUBLE)`, `created_at (TIMESTAMPTZ)`
8. **`public.ring_alerts`**: `id (UUID PK)`, `target_user_id (UUID)`, `sender_name (TEXT)`, `is_active (BOOLEAN)`, `created_at (TIMESTAMPTZ)`

## Aturan Arsitektur

1. **Flutter Berkomunikasi Langsung ke Supabase**: Semua operasi DB, auth, storage, pertemanan, geofence, riwayat rute, dan streaming lokasi ditangani oleh `SupabaseService`.
2. **Realtime WebSocket**: Stream `user_locations`, `sos_alerts`, `places`, dan `quick_checkins` mendeteksi perubahan seketika.
3. **Keamanan RLS**: Row Level Security (RLS) di PostgreSQL membatasi akses profil dan lokasi hanya untuk pengguna terotentikasi dan keluarga yang terhubung.
4. **Semua Komunikasi Terenkripsi SSL/TLS (HTTPS & WSS)**.
