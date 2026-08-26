const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('../db');
const { signToken, generateInviteCode } = require('../auth');

const router = express.Router();

function publicUser(u) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    invite_code: u.invite_code,
    avatar_version: Number(u.avatar_version || 0),
    sharing_on: u.sharing_on,
    location_precision: u.location_precision,
  };
}

// POST /api/v1/auth/register { name, email, password }
router.post('/register', async (req, res) => {
  try {
    const { name, email, password } = req.body || {};
    if (!name || !email || !password) {
      return res.status(400).json({ error: 'name, email, password wajib diisi' });
    }
    if (String(password).length < 8) {
      return res.status(400).json({ error: 'Password minimal 8 karakter' });
    }
    const normEmail = String(email).trim().toLowerCase();
    const hash = await bcrypt.hash(String(password), 10);

    let inviteCode = generateInviteCode();
    // Coba beberapa kali bila kode undangan bentrok (sangat kecil kemungkinannya).
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const { rows } = await pool.query(
          `INSERT INTO users (email, password_hash, name, invite_code)
           VALUES ($1, $2, $3, $4)
           RETURNING *`,
          [normEmail, hash, String(name).trim(), inviteCode]
        );
        const u = rows[0];
        return res.status(201).json({ token: signToken(u.id), user: publicUser(u) });
      } catch (err) {
        if (err.code === '23505') {
          if (String(err.detail || '').includes('email')) {
            return res.status(409).json({ error: 'Email sudah terdaftar' });
          }
          inviteCode = generateInviteCode(); // bentrok kode undangan → coba lagi
          continue;
        }
        throw err;
      }
    }
    return res.status(500).json({ error: 'Gagal membuat akun, coba lagi' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Kesalahan server' });
  }
});

// POST /api/v1/auth/login { email, password }
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ error: 'email dan password wajib diisi' });
    }
    const { rows } = await pool.query(
      'SELECT * FROM users WHERE email = $1',
      [String(email).trim().toLowerCase()]
    );
    const u = rows[0];
    if (!u || !(await bcrypt.compare(String(password), u.password_hash))) {
      return res.status(401).json({ error: 'Email atau password salah' });
    }
    return res.json({ token: signToken(u.id), user: publicUser(u) });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Kesalahan server' });
  }
});

module.exports = router;
