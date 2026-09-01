---
name: famloc-design
description: Panduan desain UI/UX aplikasi FamLoc (live location keluarga). Gunakan skill ini saat membuat atau mengubah screen, widget, tema, dan komponen Flutter agar tampilan konsisten dengan design system yang sudah ditetapkan.
---

# Skill: FamLoc — Desain UI/UX

## Arah Visual: "Modern Clean Family Tech"

Estetika memadukan kesederhanaan Google Maps dan kehangatan Consumer Family Apps:
- **Peta Utama Bersih**: Menggunakan palet warna Google Maps asli (jalan putih bersih, air biru pastel, taman hijau mint lembut, kontur terrain).
- **Corner Radius Besar**: 24–32dp untuk card & bottom sheet, pill (999dp) untuk tombol status & chip aksi.
- **Glassmorphism & Soft Shadow**: Floating banner dan status bar dengan `surface` putih transparan (92%) + soft shadow halus.
- **Hierarki Jelas & Ramah Lansia**: Teks nama dan indikator baterai terbaca kontras di atas peta.
- **Micro-Interactions**: Titik denyut status sharing hijau, animasi spring pada toggle, dan auto-camera glide saat mengikuti pergerakan keluarga.

---

## Design System

### Warna
| Token | Nilai | Pemakaian |
|---|---|---|
| `primary` | `#00897B` (Teal) | Elemen brand, border aktif, marker utama |
| `primaryGradient` | `#00BFA5 → #00897B` | Tombol aksi utama, FAB, kartu sorotan |
| `accentGradient` | `#7C4DFF → #00BFA5` | Hero, onboarding, progress ring |
| `secondary` | `#FFB300` (Amber) | Peringatan posisi meragukan / baterai sedang |
| `danger` | `#E53935` (Merah) | Tombol SOS darurat & hapus teman |
| `sharingActive` | `#43A047` (Hijau) | Titik denyut sharing live aktif |
| `textDark` | `#263238` | Teks utama body & title |
| `muted` | `#78909C` | Teks keterangan, timestamp relatif |

### Tipografi
- **Font Utama**: **Plus Jakarta Sans** (dibundel lokal di aset aplikasi).
- **Skala**:
  - Title AppBar: 18–20sp Bold
  - Nama Marker Peta: 12sp Bold + badge baterai
  - Detail Sheet: 20sp ExtraBold
  - Status & Kecepatan: 12.5sp SemiBold
  - Timestamp: 11.5sp Regular ("2 mnt lalu")

---

## Komponen Kunci

1. **Live Map Marker**:
   - Foto avatar bulat dengan border status (Hijau = Live < 15 mnt, Abu = Offline).
   - Label nama putih berbayang halus di bawah avatar yang memuat: `[Nama] 🔋 [Baterai]%`.
2. **Floating Status Bar (Atas)**:
   - Menampilkan status *"📍 Berbagi aktif · 🚗 45 km/jam"* atau banner darurat SOS merah berdenyut.
3. **Floating Tools (Sisi Kanan Peta)**:
   - 🚨 **Tombol SOS Merah**: Sinyal darurat sekali ketuk.
   - 📑 **Tombol Layer Peta**: Modal sheet pemilih layer (Default Jalan / Satelit / Terrain).
   - 👥 **Tombol Pemilih Keluarga**: Modal sheet untuk memilih anggota yang ingin difokuskan dan diikuti.
   - 📍 **Tombol Posisiku**: Fokus instan ke lokasi GPS sendiri.
4. **Auto-Follow Floating Pill (Bawah)**:
   - Kapsul hitam elegan: `🎥 Mengikuti [Nama] [✕]` yang muncul saat mode kamera mengikuti pergerakan aktif.
5. **Family Detail Sheet (Bawah)**:
   - Menampilkan info kecepatan (`🚗 Berkendara 45 km/jam`), jarak dari pengguna (`2.4 km dari kamu`), level baterai, dan 2 tombol utama:
     - **📍 Fokus & Ikuti** (Gradient Button)
     - **🧭 Rute Maps** (Direct Google Maps navigation launch)
