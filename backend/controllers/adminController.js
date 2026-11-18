const db = require('../config/db');

// Dashboard Quản trị viên & Giám sát DBMS
exports.getAdminOverview = async (req, res) => {
    try {
        const [[kpi]] = await db.query(`
            SELECT
                (SELECT COUNT(*) FROM users) AS total_users,
                (SELECT COUNT(*) FROM operators WHERE approval_status = 'APPROVED') AS active_operators,
                (SELECT COUNT(*) FROM bookings WHERE booking_status = 'CONFIRMED') AS confirmed_bookings,
                (SELECT COALESCE(SUM(total_amount), 0) FROM bookings WHERE booking_status = 'CONFIRMED') AS total_gmv,
                (SELECT COALESCE(SUM(commission_amount), 0) FROM bookings WHERE booking_status = 'CONFIRMED') AS total_commission,
                (SELECT COUNT(*) FROM trip_seats WHERE seat_status = 'LOCKED' AND lock_expires_at > NOW()) AS active_seat_locks
        `);

        const [operators] = await db.query('SELECT * FROM operators ORDER BY operator_id ASC');

        res.json({
            success: true,
            data: { kpi, operators }
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Duyệt / Khóa nhà xe
exports.updateOperatorStatus = async (req, res) => {
    try {
        const { operator_id, approval_status, commission_rate } = req.body;
        await db.query(
            'UPDATE operators SET approval_status = ?, commission_rate = COALESCE(?, commission_rate) WHERE operator_id = ?',
            [approval_status, commission_rate, operator_id]
        );
        await db.query(
            'INSERT INTO audit_logs(table_name, record_id, action_type, actor_info, new_values) VALUES ("operators", ?, "UPDATE", "ADMIN_RBAC", ?)',
            [operator_id, JSON.stringify({ approval_status, commission_rate })]
        );
        res.json({ success: true, message: 'Đã cập nhật trạng thái & hoa hồng nhà xe!' });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

