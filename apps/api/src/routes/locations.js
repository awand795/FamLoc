const express = require('express');
const pool = require('../db');
const { requireAuth, fuzzCoord } = require('../auth');

const router = express.Router();

function approxDistanceM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const p = Math.PI / 180;
  const dLat = (lat2 - lat1) * p;
  const dLng = (lng2 - lng1) * p;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * p) * Math.cos(lat2 * p) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// POST /api/v1/locations { lat, lng, accuracy, heading, battery, is_mocked }
router.post('/locations', requireAuth, async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT sharing_on FROM users WHERE id=$1', [req.userId]);
    if (!rows[0]) return res.status(404).json({ error: 'Pengguna tidak ditemukan' });
    if (!rows[0].sharing_on) {
      return res.status(409).json({ error: 'Sharing sedang OFF' });
    }
    const nlat = Number(req.body && req.body.lat);
    const nlng = Number(req.body && req.body.lng);
    if (!Number.isFinite(nlat) || !Number.isFinite(nlng) ||
        nlat < -90 || nlat > 90 || nlng < -180 || nlng > 180) {
      return res.status(400).json({ error: 'lat/lng tidak valid' });
    }
    const acc = req.body.accuracy != null ? Number(req.body.accuracy) : null;
    const head = req.body.heading != null ? Number(req.body.heading) : null;
    const bat = req.body.battery != null
      ? Math.max(0, Math.min(100, Math.round(Number(req.body.battery)))) : null;
    const mocked = Boolean(req.body.is_mocked);
    await pool.query(
      `INSERT INTO user_locations (user_id, geom, accuracy, heading, battery, is_mocked, updated_at)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2,$3),4326)::geography, $4,$5,$6,$7, now())
       ON CONFLICT (user_id) DO UPDATE SET geom=EXCLUDED.geom, accuracy=EXCLUDED.accuracy,
         heading=EXCLUDED.heading, battery=EXCLUDED.battery,
         is_mocked=EXCLUDED.is_mocked, updated_at=now()`,
      [req.userId, nlng, nlat, acc, head, bat, mocked]
    );
    return res.json({ ok: true });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// GET /api/v1/friends/locations — posisi terakhir semua teman yang sharing ON.
// Wajib teman mutual; hormati mode presisi 'approx' milik PEMILIK lokasi
// (server mengaburkan sebelum mengirim; posisi asli tidak keluar).
router.get('/friends/locations', requireAuth, async (req, res) => {
  try {
    const mine = await pool.query(
      `SELECT ST_Y(geom::geometry) AS lat, ST_X(geom::geometry) AS lng
       FROM user_locations WHERE user_id=$1`,
      [req.userId]
    );
    const myLat = mine.rows[0] ? Number(mine.rows[0].lat) : null;
    const myLng = mine.rows[0] ? Number(mine.rows[0].lng) : null;

    const { rows } = await pool.query(
      `SELECT u.id, u.name, u.location_precision,
              ST_Y(l.geom::geometry) AS lat, ST_X(l.geom::geometry) AS lng,
              l.accuracy, l.heading, l.battery, l.is_mocked, l.updated_at
       FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.user_id_a=$1 THEN f.user_id_b ELSE f.user_id_a END
       JOIN user_locations l ON l.user_id = u.id
       WHERE (f.user_id_a=$1 OR f.user_id_b=$1) AND u.sharing_on = TRUE`,
      [req.userId]
    );
    const friends = rows.map((r) => {
      let lat = Number(r.lat), lng = Number(r.lng);
      let fuzzed = false;
      if (r.location_precision === 'approx') {
        const fz = fuzzCoord(lat, lng, r.id);
        lat = fz.lat; lng = fz.lng;
        fuzzed = true;
      }
      return {
        id: r.id,
        name: r.name,
        location: {
          lat, lng,
          accuracy: r.accuracy == null ? null : Number(r.accuracy),
          heading: r.heading == null ? null : Number(r.heading),
          battery: r.battery == null ? null : Number(r.battery),
          is_mocked: r.is_mocked,
          updated_at: r.updated_at,
        },
        precision_fuzzed: fuzzed,
        distance_m: myLat != null
          ? Math.round(approxDistanceM(myLat, myLng, lat, lng))
          : null,
      };
    });
    return res.json({ friends });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

module.exports = router;
