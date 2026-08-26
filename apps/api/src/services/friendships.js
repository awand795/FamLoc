const pool = require('../db');

// Terima/tolak permintaan pertemanan. return { ok } atau throw { status, message }
async function respondToFriendRequest(userId, requestId, action) {
  if (!['accept', 'reject'].includes(action)) {
    throw { status: 400, message: "action harus 'accept' atau 'reject'" };
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `SELECT * FROM friend_requests
       WHERE id=$1 AND addressee_id=$2 AND status='pending' FOR UPDATE`,
      [requestId, userId]
    );
    const r = rows[0];
    if (!r) {
      await client.query('ROLLBACK');
      throw { status: 404, message: 'Permintaan tidak ditemukan/sudah diproses' };
    }
    await client.query(
      'UPDATE friend_requests SET status=$1 WHERE id=$2',
      [action === 'accept' ? 'accepted' : 'rejected', requestId]
    );
    if (action === 'accept') {
      const [a, b] = r.requester_id < r.addressee_id
        ? [r.requester_id, r.addressee_id]
        : [r.addressee_id, r.requester_id];
      await client.query(
        'INSERT INTO friendships (user_id_a, user_id_b) VALUES ($1,$2) ON CONFLICT DO NOTHING',
        [a, b]
      );
    }
    await client.query('COMMIT');
    return { ok: true, action };
  } catch (e) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw e;
  } finally {
    client.release();
  }
}

module.exports = { respondToFriendRequest };
