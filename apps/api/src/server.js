require('dotenv').config({ path: '.env.local' });
const http = require('http');
const app = require('./app');
const { setupWebSocket } = require('./websocket');

const server = http.createServer(app);
setupWebSocket(server);

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`FamLoc API & WebSocket server berjalan di port ${PORT}`);
  console.log(`Health endpoint: http://localhost:${PORT}/api/v1/health`);
  console.log(`WebSocket endpoint: ws://localhost:${PORT}/ws?token=<JWT>`);
});

