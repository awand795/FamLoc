const express = require('express');
const pool = require('../db');
const { requireAuth, areFriends } = require('../auth');
const { respondToFriendRequest } = require('../services/friendships');

const router = express.Router();

// GET /api/v1/friend-requests — incoming & outgoing pending
router.get('/friend-requests', requireAuth, async (req, res) => {
  try {
    const incoming = await pool.query(
      `SELECT fr.id, fr.created_at, u.id AS user_id, u.name, u.avatar_version
       FROM friend_requests fr JOIN users u ON u.id = fr.requester_id
       WHERE fr.addressee_id=$1 AND fr.status='pending'
       ORDER BY fr.created_at DESC`,
      [req.userId]
    );
    const outgoing = await pool.query(
      `SELECT fr.id, fr.created_at, u.id AS user_id, u.name, u.avatar_version
       FROM friend_requests fr JOIN users u ON u.id = fr.addressee_id
       WHERE fr.requester_id=$1 AND fr.status='pending'
       ORDER BY fr.created_at DESC`,
      [req.userId]
    );
    return res.json({ incoming: incoming.rows, outgoing: outgoing.rows });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// POST /api/v1/friend-requests/respond { request_id, action }
router.post('/friend-requests/respond', requireAuth, async (req, res) => {
  try {
    const { request_id, action } = req.body || {};
    const result = await respondToFriendRequest(req.userId, request_id, action);
    return res.json(result);
  } catch (err) {
    if (err && err.status) return res.status(err.status).json({ error: err.message });
    console.error(err);
    return res.status(500).json({ error: 'Kesalahan server' });
  }
});

// DELETE /api/v1/friend-requests/:id — batalkan permintaan yang dikirim sendiri (hanya pending)
router.delete('/friend-requests/:id', requireAuth, async (req, res) => {
  try {
    const { rowCount } = await pool.query(
      `DELETE FROM friend_requests
       WHERE id=$1 AND requester_id=$2 AND status='pending'`,
      [req.params.id, req.userId]
    );
    if (rowCount === 0) {
      return res.status(404).json({ error: 'Permintaan tidak ditemukan atau tidak bisa dibatalkan' });
    }
    return res.json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Kesalahan server' });
  }
});

// GET /api/v1/users/:id/avatar — publik dengan cache; URL memakai versi
router.get('/users/:id/avatar', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT image FROM user_avatars WHERE user_id=$1',
      [req.params.id]
    );
    if (!rows[0]) return res.status(404).json({ error: 'Avatar tidak ada' });
    res.set('Content-Type', 'image/jpeg');
    // Cache 7 hari — perubahan avatar otomatis "cache-bust" lewat avatar_version di URL.
    res.set('Cache-Control', 'public, max-age=604800, immutable');
    return res.send(rows[0].image);
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// GET /api/v1/reverse-geocode?lat=&lng= — Nominatim + cache DB (hormati 1 req/dtk)
let lastNominatimCall = 0;
router.get('/reverse-geocode', requireAuth, async (req, res) => {
  try {
    const lat = Number(req.query.lat), lng = Number(req.query.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res.status(400).json({ error: 'lat & lng wajib angka' });
    }
    const key = `${lat.toFixed(4)},${lng.toFixed(4)}`; // ~11 m presisi cache
    const cached = await pool.query(
      'SELECT address FROM geocode_cache WHERE lat_lng_key=$1', [key]
    );
    if (cached.rows[0]) return res.json({ address: cached.rows[0].address, cached: true });

    // Throttle best-effort 1 detik antar panggilan Nominatim.
    const wait = Math.max(0, 1000 - (Date.now() - lastNominatimCall));
    await new Promise((r) => setTimeout(r, wait));
    lastNominatimCall = Date.now();

    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${key.split(',')[0]}&lon=${key.split(',')[1]}&zoom=16&accept-language=id`;
    const resp = await fetch(url, {
      headers: { 'User-Agent': 'FamLoc/0.1 (family location sharing)' },
    });
    if (!resp.ok) throw new Error(`Nominatim ${resp.status}`);
    const data = await resp.json();
    const address = data.display_name || null;
    if (address) {
      await pool.query(
        `INSERT INTO geocode_cache (lat_lng_key, address) VALUES ($1,$2)
         ON CONFLICT (lat_lng_key) DO NOTHING`,
        [key, address]
      );
    }
    return res.json({ address, cached: false });
  } catch (err) { console.error(err); return res.status(502).json({ error: 'Gagal mengambil alamat' }); }
});

// POST /api/v1/friends/:id/location-request — minta teman nyalakan sharing
router.post('/friends/:id/location-request', requireAuth, async (req, res) => {
  try {
    const targetId = req.params.id;
    if (!(await areFriends(pool, req.userId, targetId))) {
      return res.status(403).json({ error: 'Bukan teman mutual' });
    }
    const target = await pool.query(
      'SELECT sharing_on FROM users WHERE id=$1', [targetId]
    );
    if (!target.rows[0]) return res.status(404).json({ error: 'Pengguna tidak ditemukan' });
    if (target.rows[0].sharing_on) {
      return res.status(409).json({ error: 'Teman sudah sharing' });
    }
    // Anti-spam: hapus request lama pasangan ini, cegah >1 pending.
    await pool.query(
      'DELETE FROM location_requests WHERE requester_id=$1 AND target_id=$2',
      [req.userId, targetId]
    );
    const pending = await pool.query(
      `SELECT id FROM location_requests
       WHERE requester_id=$1 AND target_id=$2 AND status='pending'`,
      [req.userId, targetId]
    );
    if (pending.rows[0]) return res.status(409).json({ error: 'Masih ada permintaan pending' });
    const { rows } = await pool.query(
      `INSERT INTO location_requests (requester_id, target_id)
       VALUES ($1,$2) RETURNING id`,
      [req.userId, targetId]
    );
    return res.status(201).json({ request_id: rows[0].id });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// POST /api/v1/location-requests/:rid { action: accept|dismiss } — hanya target
router.post('/location-requests/:rid', requireAuth, async (req, res) => {
  try {
    const action = req.body && req.body.action;
    if (!['accept', 'dismiss'].includes(action)) {
      return res.status(400).json({ error: "action harus 'accept' atau 'dismiss'" });
    }
    const { rows } = await pool.query(
      `UPDATE location_requests SET status=$1
       WHERE id=$2 AND target_id=$3 AND status='pending'
       RETURNING requester_id`,
      [action === 'accept' ? 'accepted' : 'dismissed', req.params.rid, req.userId]
    );
    if (!rows[0]) return res.status(404).json({ error: 'Permintaan tidak ditemukan/sudah diproses' });
    if (action === 'accept') {
      // Accept berarti penerima menyetujui permintaan itu → nyalakan sharing.
      await pool.query('UPDATE users SET sharing_on=TRUE WHERE id=$1', [req.userId]);
    }
    return res.json({ ok: true });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// GET /api/v1/notifications — notifikasi in-app (friend requests + location requests)
router.get('/notifications', requireAuth, async (req, res) => {
  try {
    const fr = await pool.query(
      `SELECT fr.id AS ref_id, 'friend_request' AS type, fr.created_at,
              u.id AS user_id, u.name, u.avatar_version
       FROM friend_requests fr JOIN users u ON u.id = fr.requester_id
       WHERE fr.addressee_id=$1 AND fr.status='pending'`,
      [req.userId]
    );
    const lr = await pool.query(
      `SELECT lq.id AS ref_id, 'location_request' AS type, lq.created_at,
              u.id AS user_id, u.name, u.avatar_version
       FROM location_requests lq JOIN users u ON u.id = lq.requester_id
       WHERE lq.target_id=$1 AND lq.status='pending'`,
      [req.userId]
    );
    const items = [...fr.rows, ...lr.rows].sort(
      (a, b) => new Date(b.created_at) - new Date(a.created_at)
    );
    return res.json({ notifications: items, unread_count: items.length });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

module.exports = router;
