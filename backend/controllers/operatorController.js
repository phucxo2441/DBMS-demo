const db = require('../config/db');
const callWithOutputParameters = require('../config/procedures');

// Dashboard tổng quan cho Nhà xe / Đơn vị vận hành
exports.getOperatorDashboard = async (req, res) => {
    try {
        const [revenue] = await db.query('SELECT * FROM vw_operator_revenue_report');
        const [trips] = await db.query('SELECT * FROM vw_trip_availability ORDER BY departure_time ASC');
        const [vehicles] = await db.query(`
            SELECT v.*, o.company_name
            FROM vehicles v JOIN operators o ON v.operator_id = o.operator_id
        `);
        const [passengers] = await db.query(`
            SELECT tk.ticket_code, tk.passenger_name, tk.passenger_phone, tk.pickup_point,
                   tk.checkin_status, ts.seat_code, b.booking_code, b.booking_status,
                   o.company_name, orig.name AS origin_city, dest.name AS destination_city
            FROM tickets tk
            JOIN trip_seats ts ON tk.trip_seat_id = ts.trip_seat_id
            JOIN bookings b ON tk.booking_id = b.booking_id
            JOIN trips t ON tk.trip_id = t.trip_id
            JOIN routes r ON t.route_id = r.route_id
            JOIN operators o ON r.operator_id = o.operator_id
            JOIN locations orig ON r.origin_location_id = orig.location_id
            JOIN locations dest ON r.destination_location_id = dest.location_id
            ORDER BY tk.ticket_id DESC LIMIT 30
        `);
        const [reviews] = await db.query(`
            SELECT rv.*, o.company_name, b.booking_code
            FROM reviews rv
            JOIN operators o ON rv.operator_id = o.operator_id
            JOIN bookings b ON rv.booking_id = b.booking_id
            ORDER BY rv.created_at DESC
        `);

        res.json({
            success: true,
            data: { revenue, trips, vehicles, passengers, reviews }
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Tạo chuyến đi mới & tự động sinh sơ đồ ghế trip_seats
exports.createTrip = async (req, res) => {
    const conn = await db.getConnection();
    try {
        const { route_id, vehicle_id, departure_time, arrival_time, ticket_price } = req.body;
        await conn.beginTransaction();

        const [result] = await conn.query(
            'INSERT INTO trips (route_id, vehicle_id, driver_id, departure_time, arrival_time, ticket_price) VALUES (?, ?, 1, ?, ?, ?)',
            [route_id, vehicle_id, departure_time, arrival_time, ticket_price]
        );
        const newTripId = result.insertId;

        await conn.query(`
            INSERT INTO trip_seats (trip_id, v_seat_id, seat_code, coach_or_deck, seat_tier, final_price, seat_status)
            SELECT ?, v_seat_id, seat_code, coach_or_deck, seat_tier, ROUND(? * price_multiplier, 0), 'AVAILABLE'
            FROM vehicle_seats WHERE vehicle_id = ?
        `, [newTripId, ticket_price, vehicle_id]);

        await conn.commit();
        res.json({ success: true, message: `Đã tạo chuyến mới #${newTripId} và khởi tạo sơ đồ ghế thành công!` });
    } catch (err) {
        await conn.rollback();
        res.status(500).json({ success: false, message: err.message });
    } finally {
        conn.release();
    }
};

// Soát vé QR khi hành khách lên xe/tàu
exports.scanCheckInQR = async (req, res) => {
    try {
        const { ticket_code } = req.body;
        const out = await callWithOutputParameters(
            'CALL sp_OperatorCheckInQR(?, @p_success, @p_message)',
            [ticket_code.trim()],
            'SELECT @p_success AS success, @p_message AS message'
        );
        res.json({
            success: Boolean(out.success),
            message: out.message
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};
