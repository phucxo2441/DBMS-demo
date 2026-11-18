const express = require('express');
const path = require('path');
require('dotenv').config();

const apiRoutes = require('./routes/api');
const db = require('./config/db');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, '../frontend')));

// API Routes
app.use('/api', apiRoutes);

// Healthcheck kết nối MySQL DBMS
app.get('/api/health', async (req, res) => {
    try {
        const [[row]] = await db.query('SELECT VERSION() AS mysql_version, DATABASE() AS active_db, NOW() AS db_time');
        res.json({ success: true, dbms: row });
    } catch (err) {
        console.error('[DB healthcheck] MySQL connection failed:', err);
        res.status(500).json({
            success: false,
            message: 'Không thể kết nối MySQL. Hãy kiểm tra cấu hình kết nối và các script database.'
        });
    }
});

// Background Worker mỗi 10 giây đảm bảo nhả ghế hết hạn ngay cả khi MySQL event_scheduler bị tắt
let releaseSweepRunning = false;
setInterval(async () => {
    if (releaseSweepRunning) return;
    releaseSweepRunning = true;
    let conn;
    try {
        conn = await db.getConnection();
        await conn.beginTransaction();
        const [result] = await conn.query(`
            UPDATE trip_seats
            SET seat_status = 'AVAILABLE', locked_by_session = NULL, lock_expires_at = NULL, version = version + 1
            WHERE seat_status = 'LOCKED' AND lock_expires_at <= NOW()
        `);
        if (result.affectedRows > 0) {
            await conn.query(
                'INSERT INTO audit_logs(table_name, record_id, action_type, actor_info, new_values) VALUES ("trip_seats", "AUTO_SWEEP", "AUTO_RELEASE", "BG_LOCK_WATCHDOG", ?)',
                [JSON.stringify({ released_seats: result.affectedRows })]
            );
            console.log(`[DBMS Watchdog] Đã tự động nhả ${result.affectedRows} ghế hết hạn giữ chỗ.`);
        }
        await conn.commit();
    } catch (err) {
        console.error('[DBMS Watchdog] Failed to release expired seats:', err);
        if (conn) {
            try {
                await conn.rollback();
            } catch (rollbackErr) {
                console.error('[DBMS Watchdog] Rollback failed:', rollbackErr);
            }
        }
    } finally {
        if (conn) conn.release();
        releaseSweepRunning = false;
    }
}, 10000);

app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '../frontend/index.html'));
});

app.listen(PORT, () => {
    console.log(`=========================================================`);
    console.log(`  VEXETAU DBMS DEMO SERVER ĐANG CHẠY TẠI:`);
    console.log(`  http://localhost:${PORT}`);
    console.log(`=========================================================`);
});
