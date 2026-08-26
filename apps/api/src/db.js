const { Pool } = require('pg');

if (!process.env.DATABASE_URL) {
  // Muat .env.local (lokal) bila ada; di Vercel env var disuntik otomatis.
  try { require('dotenv').config({ path: '.env.local' }); } catch (_) {}
}

// Aiven memakai CA self-signed: verifikasi sertifikat dimatikan,
// enkripsi TLS tetap aktif. sslmode dihapus dari URL agar pg tidak
// memaksakan verify-full.
let connectionString = process.env.DATABASE_URL || '';
connectionString = connectionString.replace(/sslmode=[^&]*/g, '').replace(/&&+/g, '&');

const pool = new Pool({
  connectionString,
  max: 5,
  ssl: { rejectUnauthorized: false },
});

module.exports = pool;
