const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();
router.use(requireAuth);

// GET /api/v1/me — profil sendiri + jadwal
router.get('/', async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT u.*, s.days, s.start_time::text AS start_time,
              s.end_time::text AS end_time, s.enabled AS schedule_enabled
       FROM users u
       LEFT JOIN sharing_schedules s ON s.user_id = u.id
       WHERE u.id = $1`,
      [req.userId]
    );
    if (!rows[0]) return res.status(404).json({ error: 'Pengguna tidak ditemukan' });
    const u = rows[0];
    return res.json({
      user: {
        id: u.id, email: u.email, name: u.name,
        invite_code: u.invite_code,
        avatar_version: Number(u.avatar_version || 0),
        sharing_on: u.sharing_on,
        location_precision: u.location_precision,
      },
      schedule: u.days ? {
        days: u.days, start_time: u.start_time,
        end_time: u.end_time, enabled: u.schedule_enabled,
      } : null,
    });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// PATCH /api/v1/me/sharing { sharing_on }
router.patch('/sharing', async (req, res) => {
  try {
    const on = Boolean(req.body && req.body.sharing_on);
    const { rows } = await pool.query(
      'UPDATE users SET sharing_on=$1 WHERE id=$2 RETURNING sharing_on',
      [on, req.userId]
    );
    return res.json({ sharing_on: rows[0].sharing_on });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// PATCH /api/v1/me/precision { mode: 'exact'|'approx' }
router.patch('/precision', async (req, res) => {
  try {
    const mode = req.body && req.body.mode;
    if (!['exact', 'approx'].includes(mode)) {
      return res.status(400).json({ error: "mode harus 'exact' atau 'approx'" });
    }
    const { rows } = await pool.query(
      'UPDATE users SET location_precision=$1 WHERE id=$2 RETURNING location_precision',
      [mode, req.userId]
    );
    return res.json({ location_precision: rows[0].location_precision });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// PATCH /api/v1/me/password { old_password, new_password }
router.patch('/password', async (req, res) => {
  try {
    const { old_password, new_password } = req.body || {};
    if (!old_password || !new_password || String(new_password).length < 8) {
      return res.status(400).json({ error: 'Password baru minimal 8 karakter' });
    }
    const { rows } = await pool.query(
      'SELECT password_hash FROM users WHERE id=$1', [req.userId]
    );
    if (!rows[0] || !(await bcrypt.compare(String(old_password), rows[0].password_hash))) {
      return res.status(403).json({ error: 'Password lama salah' });
    }
    const hash = await bcrypt.hash(String(new_password), 10);
    await pool.query('UPDATE users SET password_hash=$1 WHERE id=$2', [hash, req.userId]);
    return res.json({ ok: true });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// PUT /api/v1/me/avatar { image_base64 } — JPEG ≤100KB setelah decode
router.put('/avatar', async (req, res) => {
  try {
    const b64 = req.body && req.body.image_base64;
    if (!b64 || typeof b64 !== 'string') {
      return res.status(400).json({ error: 'image_base64 wajib diisi' });
    }
    const buf = Buffer.from(b64, 'base64');
    if (buf.length === 0 || buf.length > 102400) {
      return res.status(413).json({ error: 'Ukuran avatar maksimal 100KB' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO user_avatars (user_id, image, updated_at)
         VALUES ($1, $2, now())
         ON CONFLICT (user_id) DO UPDATE SET image=$2, updated_at=now()`,
        [req.userId, buf]
      );
      const { rows } = await client.query(
        'UPDATE users SET avatar_version = avatar_version + 1 WHERE id=$1 RETURNING avatar_version',
        [req.userId]
      );
      await client.query('COMMIT');
      return res.json({ avatar_version: Number(rows[0].avatar_version) });
    } catch (e) { await client.query('ROLLBACK'); throw e; }
    finally { client.release(); }
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// PUT /api/v1/me/schedule { days, start_time, end_time, enabled } | null (hapus)
router.put('/schedule', async (req, res) => {
  try {
    const body = req.body;
    if (body == null || body.schedule == null) {
      await pool.query('DELETE FROM sharing_schedules WHERE user_id=$1', [req.userId]);
      return res.json({ schedule: null });
    }
    const s = body.schedule;
    if (!Array.isArray(s.days) || !s.start_time || !s.end_time ||
        !/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(s.start_time) ||
        !/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(s.end_time)) {
      return res.status(400).json({ error: 'Format jadwal tidak valid' });
    }
    const days = [...new Set(s.days.map(Number))].filter((d) => d >= 0 && d <= 6);
    if (!days.length) return res.status(400).json({ error: 'Minimal pilih satu hari' });
    const start = s.start_time.length === 5 ? `${s.start_time}:00` : s.start_time;
    const end = s.end_time.length === 5 ? `${s.end_time}:00` : s.end_time;
    const { rows } = await pool.query(
      `INSERT INTO sharing_schedules (user_id, days, start_time, end_time, enabled)
       VALUES ($1,$2,$3::time,$4::time,$5)
       ON CONFLICT (user_id) DO UPDATE
         SET days=$2, start_time=$3::time, end_time=$4::time, enabled=$5
       RETURNING days, start_time::text AS start_time, end_time::text AS end_time, enabled`,
      [req.userId, days, start, end, s.enabled !== false]
    );
    return res.json({
      schedule: {
        days: rows[0].days, start_time: rows[0].start_time,
        end_time: rows[0].end_time, enabled: rows[0].enabled,
      },
    });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

module.exports = router;
