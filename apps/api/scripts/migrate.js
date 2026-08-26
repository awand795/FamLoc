// Menjalankan semua .sql di migrations/ secara berurutan (urut nama file).
// Aman dijalankan ulang: gunakan IF NOT EXISTS.
require('dotenv').config({ path: '.env.local' });
const fs = require('fs');
const path = require('path');
const pool = require('../src/db');

async function main() {
  const dir = path.join(__dirname, '..', 'migrations');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  if (!files.length) { console.log('Tidak ada migration.'); return; }
  for (const file of files) {
    const sql = fs.readFileSync(path.join(dir, file), 'utf8');
    console.log(`→ Menjalankan ${file} ...`);
    try {
      await pool.query(sql);
      console.log(`  OK: ${file}`);
    } catch (err) {
      console.error(`  GAGAL ${file}:`, err.message);
      process.exitCode = 1;
      return;
    }
  }
  console.log('Semua migration selesai.');
}

main().then(() => pool.end()).catch((e) => { console.error(e); pool.end(); });
