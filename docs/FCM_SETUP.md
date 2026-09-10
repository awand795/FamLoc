# Menyalakan FCM FamLoc

1. Buat/masuk ke proyek Firebase dan tambahkan aplikasi Android dengan package `eu.awanda.famloc`. Download `google-services.json` lalu simpan di `apps/mobile/android/app/google-services.json`. File tersebut diabaikan Git dan plugin Google Services Kotlin DSL sudah dikonfigurasi.
2. Buat Service Account JSON di Firebase Console. Simpan isinya sebagai Supabase secret, **jangan** commit ke repositori:

   ```powershell
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
   supabase functions deploy send-family-push
   ```

3. Build aplikasi seperti biasa; konfigurasi Android dibaca otomatis dari `google-services.json`:

   ```powershell
   flutter build apk --release
   ```

4. Terapkan migrasi `20260910_device_tokens.sql`, install APK baru di setiap HP, login, lalu setujui notifikasi dan lokasi sepanjang waktu pada HP yang dilacak.

FCM menangani SOS, check-in, geofence, dan ring pada HP penerima yang aplikasinya tidak sedang dibuka. Tracking lokasi pengirim tetap memerlukan foreground service Android dan izin lokasi sepanjang waktu.
