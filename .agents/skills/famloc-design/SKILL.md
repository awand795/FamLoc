---
name: famloc-design
description: Panduan desain UI/UX aplikasi FamLoc (live location keluarga). Gunakan skill ini saat membuat atau mengubah screen, widget, tema, dan komponen Flutter agar tampilan konsisten dengan design system yang sudah ditetapkan.
---

# Skill: FamLoc — Desain UI/UX

## Arah Visual: "Modern Family Tech" (ala Dribbble)

Estetika seperti shot populer di Dribbble untuk app consumer tech:
- **Gradient sebagai identitas**: tombol utama, FAB, header card memakai gradient (bukan warna flat).
- **Corner radius besar**: 24–32dp untuk card & sheet, pill (999dp) untuk tombol & chip.
- **Glassmorphism halus**: bottom sheet & banner dengan `surface` semi-transparan + blur (BackdropFilter) di atas peta.
- **Soft shadow berlapis**: bayangan lembut warna-tinted (shadow dari warna brand, bukan hitam pekat), offset besar + blur besar + opacity rendah.
- **Playful tapi rapi**: ilustrasi/emoji secukupnya, spacing lega, hierarki tegas.
- **Micro-interaction**: toggle sharing memantul halus (spring), marker muncul dengan scale-in, dot "live" berdenyut.
- Tetap **kontras & terbaca**: teks utama gelap di atas surface; jangan korbankan keterbacaan demi gaya (ada pengguna lansia).

## Prinsip Desain

1. **Privasi terlihat, bukan tersembunyi.** Status "lokasimu sedang dibagikan" harus SELALU terlihat di layar utama. Pengguna tidak boleh lupa bahwa sharing aktif.
2. **Ramah keluarga**: teks besar & jelas (ada pengguna lansia), ikon + label (jangan ikon saja), bahasa Indonesia yang hangat.
3. **Peta adalah layar utama** — semua fitur lain sekunder terhadap peta.
4. **Tenang, bukan alarm.** Ini app pemantauan keluarga, bukan CCTV: hindari estetika survaillance (warna merah untuk aksesori biasa), gunakan nuansa aman & hangat.

## Design System

### Warna
| Token | Nilai | Pemakaian |
|---|---|---|
| `primary` | Teal/hijau tosca (`#00897B`) | Marker aktif, ikon, brand solid |
| `primaryGradient` | `#00BFA5 → #00897B` (atas→bawah) | Tombol utama, FAB, header card |
| `accentGradient` | `#7C4DFF → #00BFA5` (kiri→kanan) | Hero/onboarding, badge premium, progress ring |
| `secondary` | Amber hangat (`#FFB300`) | Aksen, indikator "terakhir terlihat" |
| `surface` | Putih/off-white (`#FAFAF8`) | Card, sheet (semi-transparan + blur saat di atas peta) |
| `danger` | Merah lembut (`#E53935`) | HANYA untuk SOS & unfriend/block |
| `sharingActive` | Hijau (`#43A047`) + titik berdenyut | Badge sharing ON |
| Teks gelap | `#263238` | Body text |
| Shadow tint | `#00897B @ 18%` | Bayangan lembut elemen brand (bukan hitam) |

### Tipografi
- Font: **Plus Jakarta Sans** (utama, support Indonesia) — Display/pemuka pakai weight **ExtraBold** dengan tracking rapat ala Dribbble; body pakai Regular/Medium.
- Skala: headline 28–32sp ExtraBold · judul section 20sp Bold · body 15sp Medium · caption/timestamp 12sp Regular.
- Nama di map marker: 14sp semibold dengan halo/outline putih agar terbaca di atas tile peta.
- Timestamp "terakhir dilihat": 12sp regular, format relatif ("5 mnt lalu").

### Komponen Kunci
- **MapMarker teman**: lingkaran avatar (48dp) + border warna sesuai status (aktif = primaryGradient, stale > 15 mnt = abu) + label nama; pin drop shadow tinted; muncul dengan animasi scale-in.
- **SharingToggle**: switch besar bergaya pill-gradient di home app bar; saat ON tampilkan banner glassmorphism tipis "📍 Lokasimu dibagikan ke {N} orang · ketuk untuk matikan".
- **BottomSheet detail teman** (drag dari marker): rounded-top 28dp, foto, nama, alamat kasar, akurasi ±Xm, update terakhir, tombol "Lihat rute" (pill gradient).
- **FriendCard**: card radius 24dp + soft shadow tinted, daftar teman mutual dengan status lokasi (live / offline); avatar dengan ring gradient saat live. Sertakan: chip status (🚗 Bergerak · 🏠 Diam · ⏸ Offline) + ikon baterai dengan persentase. Jika teman offline: tombol sekunder "Minta lokasi"; jika `is_mocked`: badge ⚠️ kecil "posisi mungkin tidak akurat" (amber, bukan merah).
- **Tombol utama**: pill full-rounded, gradient primary, teks putih semibold, pressed = scale 0.97.
- **Chip status**: pill kecil dengan background tint 10% warna status; warna: bergerak = primaryGradient tint, diam = abu netral, offline = abu redup.
- **Indikator baterai**: ikon baterai kecil di samping nama pada FriendCard & bottom sheet detail teman; <20% = amber (secondary), bukan merah (merah hanya SOS).

## Daftar Screen (MVP)

1. **Splash/Onboarding** — 3 slide: apa itu app, privasi ("hanya teman yang bisa lihat"), izin lokasi.
2. **Login/Daftar** — email + password → lengkapi profil; hero gradient + ilustrasi playful ala Dribbble.
3. **Map Home** ⭐ — peta fullscreen, FAB toggle sharing, search bar teman, bottom sheet daftar teman.
4. **Keluargaku** — daftar semua teman: chip status (bergerak/diam/offline), ikon baterai, jarak "X km dari kamu".
5. **Tambah Teman** — tab: QR code saya / Scan QR / link undangan.
6. **Permintaan Pertemanan** — list incoming/outgoing, accept/reject.
7. **Profil & Privasi** — edit profil, ganti password, toggle presisi lokasi (📍 Akurat / 🌫️ Kasar ±500m dengan penjelasan singkat), jadwal sharing otomatis (pilih hari + time-picker bergaya pill), riwayat sharing, blokir, logout.
8. **Notifikasi in-app** — list: permintaan pertemanan, "X minta lihat lokasimu" dengan tombol cepat "Nyalakan sharing" / abaikan.

### Avatar fallback
- Jika belum upload foto: lingkaran gradient primaryGradient berisi inisial nama putih ExtraBold — tetap terlihat Dribbble-worthy tanpa file gambar.

## Aturan Interaksi

- Izin lokasi diminta dengan **pre-permission dialog** penjelasan sebelum dialog OS.
- Saat sharing OFF: peta tetap bisa dilihat, marker sendiri disembunyikan, tampilkan CTA "Nyalakan berbagi lokasi".
- Polling indicator halus: dot kecil berputar di app bar saat refresh posisi (transparan soal aktivitas).
- Empty state ramah: "Belum punya teman? Tambahkan keluargamu dengan QR code 👋".
- Dark mode: dukung, tapi peta tetap light style secara default (keterbacaan marker).
