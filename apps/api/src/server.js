require('dotenv').config({ path: '.env.local' });
const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`FamLoc API lokal berjalan di http://localhost:${PORT}/api/v1/health`);
});
