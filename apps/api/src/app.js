const express = require('express');

const authRoutes = require('./routes/auth');
const meRoutes = require('./routes/me');
const friendsRouter = require('./routes/friends');
const locationsRouter = require('./routes/locations');
const miscRouter = require('./routes/misc');

const app = express();
app.use(express.json({ limit: '512kb' }));

// Health check
app.get('/api/v1/health', (req, res) => res.json({ ok: true, service: 'famloc-api' }));

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/me', meRoutes);
app.use('/api/v1/friends', friendsRouter);   // request/list/unfriend + location-request
app.use('/api/v1', locationsRouter);          // POST /locations, GET /friends/locations
app.use('/api/v1', miscRouter);               // avatar, reverse-geocode,
                                              // friend-requests, location-requests,
                                              // notifications

// Error handler terakhir
app.use((err, req, res, next) => {
  console.error(err);
  if (res.headersSent) return next(err);
  return res.status(500).json({ error: 'Kesalahan server' });
});

module.exports = app;
