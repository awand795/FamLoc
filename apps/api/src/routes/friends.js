const express = require('express');
const pool = require('../db');
const { requireAuth, areFriends } = require('../auth');
const { respondToFriendRequest } = require('../services/friendships');

const router = express.Router();
router.use(requireAuth);


// POST /api/v1/friends/request { target_user_id | invite_code }
router.post('/request', async (req, res) => {
  try {
    let targetId = req.body && req.body.target_user_id;
    if (!targetId && req.body && req.body.invite_code) {
      const { rows } = await pool.query(
        'SELECT id FROM users WHERE invite_code = $1',
        [String(req.body.invite_code).trim().toUpperCase()]
      );
      if (!rows[0]) return res.status(404).json({ error: 'Kode undangan tidak ditemukan' });
      targetId = rows[0].id;
    }
    if (!targetId) return res.status(400).json({ error: 'target_user_id atau invite_code wajib' });
    if (targetId === req.userId) {
      return res.status(400).json({ error: 'Tidak bisa menambahkan diri sendiri' });
    }
    if (await areFriends(pool, req.userId, targetId)) {
      return res.status(409).json({ error: 'Sudah berteman' });
    }
    // Hapus request lama antar pasangan ini lalu buat baru.
    await pool.query(
      `DELETE FROM friend_requests
       WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)`,
      [req.userId, targetId]
    );
    const { rows } = await pool.query(
      `INSERT INTO friend_requests (requester_id, addressee_id)
       VALUES ($1,$2) RETURNING id, created_at`,
      [req.userId, targetId]
    );
    const target = await pool.query('SELECT name FROM users WHERE id=$1', [targetId]);
    return res.status(201).json({
      request_id: rows[0].id,
      target_name: target.rows[0] ? target.rows[0].name : null,
      status: 'pending',
    });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// POST /api/v1/friends/respond { request_id, action: accept|reject }
router.post('/respond', async (req, res) => {
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

// GET /api/v1/friends — daftar teman mutual + status lokasi ringkas
router.get('/', async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT u.id, u.name, u.avatar_version, u.sharing_on,
              ST_Y(l.geom::geometry) AS lat, ST_X(l.geom::geometry) AS lng,
              l.accuracy, l.heading, l.battery, l.is_mocked, l.updated_at
       FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.user_id_a=$1 THEN f.user_id_b ELSE f.user_id_a END
       LEFT JOIN user_locations l ON l.user_id = u.id
       WHERE f.user_id_a=$1 OR f.user_id_b=$1
       ORDER BY u.name`,
      [req.userId]
    );
    return res.json({
      friends: rows.map((r) => ({
        id: r.id,
        name: r.name,
        avatar_version: Number(r.avatar_version || 0),
        sharing_on: r.sharing_on,
        location: r.lat != null ? {
          lat: Number(r.lat), lng: Number(r.lng),
          accuracy: r.accuracy, heading: r.heading,
          battery: r.battery == null ? null : Number(r.battery),
          is_mocked: r.is_mocked,
          updated_at: r.updated_at,
        } : null,
      })),
    });
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

// DELETE /api/v1/friends/:id — unfriend dua arah
router.delete('/:id', async (req, res) => {
  try {
    const other = req.params.id;
    const [a, b] = req.userId < other ? [req.userId, other] : [other, req.userId];
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM friendships WHERE user_id_a=$1 AND user_id_b=$2', [a, b]);
      await client.query(
        `DELETE FROM friend_requests
         WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)`,
        [req.userId, other]
      );
      await client.query('COMMIT');
      return res.json({ ok: true });
    } catch (e) { await client.query('ROLLBACK'); throw e; }
    finally { client.release(); }
  } catch (err) { console.error(err); return res.status(500).json({ error: 'Kesalahan server' }); }
});

module.exports = router;
