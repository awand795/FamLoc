const { WebSocketServer, WebSocket } = require('ws');
const url = require('url');
const pool = require('./db');
const { verifyToken, fuzzCoord } = require('./auth');

// Map userId -> Set of active WebSocket connections (support multi-device)
const clients = new Map();

function addClient(userId, ws) {
  if (!clients.has(userId)) {
    clients.set(userId, new Set());
  }
  clients.get(userId).add(ws);
}

function removeClient(userId, ws) {
  if (clients.has(userId)) {
    const userSet = clients.get(userId);
    userSet.delete(ws);
    if (userSet.size === 0) {
      clients.delete(userId);
    }
  }
}

function sendJson(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

function broadcastToUser(userId, data) {
  const userSet = clients.get(userId);
  if (!userSet) return;
  for (const ws of userSet) {
    sendJson(ws, data);
  }
}

async function handleLocationUpdate(userId, payload) {
  const nlat = Number(payload && payload.lat);
  const nlng = Number(payload && payload.lng);
  if (!Number.isFinite(nlat) || !Number.isFinite(nlng) ||
      nlat < -90 || nlat > 90 || nlng < -180 || nlng > 180) {
    return;
  }

  // Cek user status
  const userRes = await pool.query(
    'SELECT name, sharing_on, location_precision FROM users WHERE id=$1',
    [userId]
  );
  const user = userRes.rows[0];
  if (!user || !user.sharing_on) return;

  const acc = payload.accuracy != null ? Number(payload.accuracy) : null;
  const head = payload.heading != null ? Number(payload.heading) : null;
  const bat = payload.battery != null
    ? Math.max(0, Math.min(100, Math.round(Number(payload.battery)))) : null;
  const mocked = Boolean(payload.is_mocked);

  // Simpan ke PostgreSQL
  await pool.query(
    `INSERT INTO user_locations (user_id, geom, accuracy, heading, battery, is_mocked, updated_at)
     VALUES ($1, ST_SetSRID(ST_MakePoint($2,$3),4326)::geography, $4,$5,$6,$7, now())
     ON CONFLICT (user_id) DO UPDATE SET geom=EXCLUDED.geom, accuracy=EXCLUDED.accuracy,
       heading=EXCLUDED.heading, battery=EXCLUDED.battery,
       is_mocked=EXCLUDED.is_mocked, updated_at=now()`,
    [userId, nlng, nlat, acc, head, bat, mocked]
  );

  // Cari mutual friends yang sedang online
  const friendsRes = await pool.query(
    `SELECT CASE WHEN f.user_id_a=$1 THEN f.user_id_b ELSE f.user_id_a END AS friend_id
     FROM friendships f
     WHERE f.user_id_a=$1 OR f.user_id_b=$1`,
    [userId]
  );

  const updatedAt = new Date().toISOString();

  for (const row of friendsRes.rows) {
    const friendId = row.friend_id;
    if (clients.has(friendId)) {
      let sendLat = nlat;
      let sendLng = nlng;
      let fuzzed = false;

      if (user.location_precision === 'approx') {
        const fz = fuzzCoord(sendLat, sendLng, userId);
        sendLat = fz.lat;
        sendLng = fz.lng;
        fuzzed = true;
      }

      broadcastToUser(friendId, {
        type: 'friend:location_updated',
        payload: {
          id: userId,
          name: user.name,
          location: {
            lat: sendLat,
            lng: sendLng,
            accuracy: acc,
            heading: head,
            battery: bat,
            is_mocked: mocked,
            updated_at: updatedAt,
          },
          precision_fuzzed: fuzzed,
        },
      });
    }
  }
}

function setupWebSocket(server) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const parsed = url.parse(request.url, true);
    if (parsed.pathname === '/ws' || parsed.pathname === '/api/v1/ws') {
      const token = parsed.query && parsed.query.token;
      const userId = token ? verifyToken(token) : null;

      if (!userId) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }

      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request, userId);
      });
    } else {
      socket.destroy();
    }
  });

  wss.on('connection', (ws, req, userId) => {
    ws.userId = userId;
    ws.isAlive = true;
    addClient(userId, ws);

    sendJson(ws, {
      type: 'connected',
      payload: { userId, message: 'FamLoc Realtime WebSocket Connected' },
    });

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message.toString());
        if (data.type === 'ping') {
          sendJson(ws, { type: 'pong', timestamp: Date.now() });
        } else if (data.type === 'location:update') {
          await handleLocationUpdate(userId, data.payload);
        }
      } catch (err) {
        console.error('WebSocket message error:', err);
      }
    });

    ws.on('close', () => {
      removeClient(userId, ws);
    });

    ws.on('error', (err) => {
      console.error(`WebSocket error for user ${userId}:`, err);
      removeClient(userId, ws);
    });
  });

  // Heartbeat interval (setiap 30 detik)
  const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) {
        if (ws.userId) removeClient(ws.userId, ws);
        return ws.terminate();
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, 30000);

  wss.on('close', () => {
    clearInterval(interval);
  });

  return { wss, broadcastToUser };
}

module.exports = { setupWebSocket, broadcastToUser, handleLocationUpdate, clients };

