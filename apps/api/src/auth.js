const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

function signToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '90d' });
}

// Middleware: wajib Bearer token valid. req.userId terisi.
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token tidak ditemukan' });
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub;
    next();
  } catch (_) {
    return res.status(401).json({ error: 'Token tidak valid atau kedaluwarsa' });
  }
}

// Kode undangan pendek unik (base32 tanpa karakter membingungkan).
function generateInviteCode() {
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 8; i++) code += alphabet[crypto.randomInt(alphabet.length)];
  return code;
}

// Fuzz deterministik ±500m dari koordinat (stabil antar polling).
// Sumber keacakan: hash user_id, bukan waktu — marker tidak "loncat".
function fuzzCoord(lat, lng, userIdSeed) {
  const h = crypto.createHash('md5').update(String(userIdSeed)).digest();
  const a = (h.readUInt16BE(0) / 0xffff - 0.5) * 2; // -1..1
  const b = (h.readUInt16BE(2) / 0xffff - 0.5) * 2;
  const dLat = a * 0.0045; // ~±500 m
  const dLng = b * 0.0045;
  return { lat: +(lat + dLat).toFixed(6), lng: +(lng + dLng).toFixed(6) };
}

async function areFriends(pool, a, b) {
  const [x, y] = a < b ? [a, b] : [b, a];
  const { rowCount } = await pool.query(
    'SELECT 1 FROM friendships WHERE user_id_a=$1 AND user_id_b=$2',
    [x, y]
  );
  return rowCount > 0;
}

function verifyToken(token) {
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    return payload.sub;
  } catch (_) {
    return null;
  }
}

module.exports = { signToken, verifyToken, requireAuth, generateInviteCode, fuzzCoord, areFriends };

