---
name: famloc-stack
description: Tech stack dan arsitektur aplikasi FamLoc (live location keluarga). Gunakan skill ini saat menulis kode, mengatur database, deploy, atau memutuskan hal teknis apa pun di project ini agar konsisten dengan keputusan yang sudah dikunci.
---

# Skill: FamLoc — Stack & Arsitektur (Supabase Realtime)

## Keputusan Terkunci

| Komponen | Pilihan | Catatan |
|---|---|---|
| Mobile app | **Flutter (Dart)** | Satu codebase Android + iOS |
| Backend & Database | **Supabase (BaaS)** | 100% Serverless. Mengelola Database PostgreSQL + PostGIS, Auth, Storage, dan Realtime WebSocket |
| Realtime Live Tracking | **Supabase Realtime (WebSocket)** | Menggunakan Postgres Changes stream & WebSocket duplex via `supabase_flutter` |
| Auth | **Supabase Auth** | Email + Password bawaan Supabase, sesi persisten |
| Storage Avatar | **Supabase Storage** | Bucket `avatars` publik untuk foto profil |
| Map SDK | **flutter_map + tile OpenStreetMap** | Gratis, tanpa API key. WAJIB sertakan atribusi © OpenStreetMap contributors |
| Penggunaan | **Keluarga (Anda & Mama)** | Saling berbagi lokasi secara langsung dan realtime tanpa perantara backend terpisah |

## Aturan Arsitektur

1. **Flutter berkomunikasi langsung ke Supabase**: Semua operasi DB, auth, storage, dan streaming lokasi ditangani oleh `SupabaseService`.
2. **Realtime WebSocket**: Stream `user_locations` mendeteksi pergerakan anggota keluarga secara instan.
3. **Keamanan**: Row Level Security (RLS) di PostgreSQL membatasi akses profil dan lokasi hanya untuk pengguna terotentikasi.
4. **Semua komunikasi terenkripsi SSL/TLS (HTTPS & WSS)**.
