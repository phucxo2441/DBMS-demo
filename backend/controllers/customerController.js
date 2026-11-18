const db = require('../config/db');
const callWithOutputParameters = require('../config/procedures');

// Lấy danh mục tỉnh thành, nhà xe, banner, chính sách hủy
exports.getBootstrapData = async (req, res) => {
    try {
        const [locations] = await db.query('SELECT * FROM locations ORDER BY name');
        const [operators] = await db.query('SELECT operator_id, company_name, transport_category, rating_avg, total_reviews FROM operators WHERE approval_status = "APPROVED"');
        const [banners] = await db.query('SELECT * FROM banners_news WHERE is_active = TRUE ORDER BY item_id DESC');
        const [policies] = await db.query('SELECT * FROM cancellation_policies ORDER BY hours_before_departure DESC');
        const [promos] = await db.query('SELECT promo_code, discount_type, discount_value, min_order_amount, max_discount_amount FROM promotions WHERE is_active = TRUE AND valid_to > NOW()');
        const [user] = await db.query('SELECT user_id, full_name, email, phone, loyalty_points FROM users WHERE user_id = 1');

        res.json({
            success: true,
            data: { locations, operators, banners, policies, promos, currentUser: user[0] || null }
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Tìm kiếm chuyến đi qua SQL View vw_trip_availability
exports.searchTrips = async (req, res) => {
    try {
        const { origin_id, destination_id, category, sort_by } = req.query;
        let sql = 'SELECT * FROM vw_trip_availability WHERE trip_status = "SCHEDULED"';
        const params = [];

        if (origin_id) {
            sql += ' AND origin_id = ?';
            params.push(origin_id);
        }
        if (destination_id) {
            sql += ' AND destination_id = ?';
            params.push(destination_id);
        }
        if (category && category !== 'ALL') {
            sql += ' AND transport_category = ?';
            params.push(category);
        }

        if (sort_by === 'PRICE_ASC') sql += ' ORDER BY ticket_price ASC';
        else if (sort_by === 'PRICE_DESC') sql += ' ORDER BY ticket_price DESC';
        else if (sort_by === 'DURATION') sql += ' ORDER BY estimated_duration_mins ASC';
        else sql += ' ORDER BY departure_time ASC';

        const [trips] = await db.query(sql, params);
        res.json({ success: true, sql_executed: sql, data: trips });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Lấy sơ đồ ghế thời gian thực của 1 chuyến
exports.getTripSeats = async (req, res) => {
    try {
        const { tripId } = req.params;
        // Nhả ghế hết hạn trước khi trả dữ liệu (phòng trường hợp event_scheduler chưa bật trên máy local)
        await db.query(`
            UPDATE trip_seats
            SET seat_status = 'AVAILABLE', locked_by_session = NULL, lock_expires_at = NULL, version = version + 1
            WHERE trip_id = ? AND seat_status = 'LOCKED' AND lock_expires_at <= NOW()
        `, [tripId]);

        const [seats] = await db.query(
            'SELECT trip_seat_id, seat_code, coach_or_deck, seat_tier, final_price, seat_status, locked_by_session, lock_expires_at, version FROM trip_seats WHERE trip_id = ? ORDER BY coach_or_deck, seat_code',
            [tripId]
        );
        res.json({ success: true, data: seats });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Gọi Stored Procedure sp_HoldSeatWithLock (Pessimistic Locking SELECT FOR UPDATE)
exports.holdSeat = async (req, res) => {
    try {
        const { trip_id, seat_code, session_id, hold_seconds = 120 } = req.body;
        const out = await callWithOutputParameters(
            'CALL sp_HoldSeatWithLock(?, ?, ?, ?, @p_success, @p_message, @p_expires_at)',
            [trip_id, seat_code, session_id, hold_seconds],
            'SELECT @p_success AS success, @p_message AS message, @p_expires_at AS expires_at'
        );

        res.json({
            success: Boolean(out.success),
            message: out.message,
            expires_at: out.expires_at,
            db_procedure: `CALL sp_HoldSeatWithLock(${trip_id}, '${seat_code}', '${session_id}', ${hold_seconds})`
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Nhả ghế thủ công
exports.releaseSeat = async (req, res) => {
    try {
        const { trip_id, seat_code, session_id } = req.body;
        await db.query('CALL sp_ReleaseSeat(?, ?, ?)', [trip_id, seat_code, session_id]);
        res.json({ success: true, message: `Đã nhả ghế ${seat_code}` });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Gọi Stored Procedure sp_ConfirmBookingAndPay (ACID Transaction)
exports.confirmBooking = async (req, res) => {
    try {
        const {
            user_id = 1,
            session_id,
            trip_id,
            seat_codes,
            contact_name,
            contact_phone,
            contact_email,
            pickup_point,
            dropoff_point,
            promo_code = '',
            use_points = 0,
            payment_method = 'VNPAY',
            booking_channel = 'WEB_APP',
            vat_requested = false,
            vat_tax_code = '',
            vat_company = ''
        } = req.body;

        const seatCsv = Array.isArray(seat_codes) ? seat_codes.join(',') : seat_codes;

        const out = await callWithOutputParameters(
            'CALL sp_ConfirmBookingAndPay(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, @p_success, @p_message, @p_booking_code)',
            [
                user_id, session_id, trip_id, seatCsv,
                contact_name, contact_phone, contact_email,
                pickup_point, dropoff_point, promo_code,
                use_points, payment_method, booking_channel,
                vat_requested ? 1 : 0, vat_tax_code, vat_company
            ],
            'SELECT @p_success AS success, @p_message AS message, @p_booking_code AS booking_code'
        );
        res.json({
            success: Boolean(out.success),
            message: out.message,
            booking_code: out.booking_code,
            db_procedure: 'sp_ConfirmBookingAndPay (ACID Transaction)'
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Tra cứu vé bằng Mã đặt chỗ + SĐT
exports.lookupBooking = async (req, res) => {
    try {
        const { booking_code, phone } = req.query;
        const [bookings] = await db.query(
            'SELECT * FROM bookings WHERE booking_code = ? AND contact_phone = ?',
            [booking_code, phone]
        );
        if (bookings.length === 0) {
            return res.json({ success: false, message: 'Không tìm thấy đơn đặt vé phù hợp!' });
        }

        const booking = bookings[0];
        const [tickets] = await db.query(`
            SELECT tk.*, ts.seat_code, ts.coach_or_deck, t.departure_time, t.arrival_time,
                   o.company_name, orig.name AS origin_city, dest.name AS destination_city
            FROM tickets tk
            JOIN trip_seats ts ON tk.trip_seat_id = ts.trip_seat_id
            JOIN trips t ON tk.trip_id = t.trip_id
            JOIN routes r ON t.route_id = r.route_id
            JOIN operators o ON r.operator_id = o.operator_id
            JOIN locations orig ON r.origin_location_id = orig.location_id
            JOIN locations dest ON r.destination_location_id = dest.location_id
            WHERE tk.booking_id = ?
        `, [booking.booking_id]);

        const [payments] = await db.query('SELECT * FROM payments WHERE booking_id = ?', [booking.booking_id]);

        res.json({ success: true, data: { booking, tickets, payments } });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Hủy vé & hoàn tiền qua Stored Procedure sp_CancelBookingAndRefund
exports.cancelBooking = async (req, res) => {
    try {
        const { booking_code, phone } = req.body;
        const out = await callWithOutputParameters(
            'CALL sp_CancelBookingAndRefund(?, ?, @p_success, @p_message, @p_refund)',
            [booking_code, phone],
            'SELECT @p_success AS success, @p_message AS message, @p_refund AS refund_amount'
        );
        res.json({
            success: Boolean(out.success),
            message: out.message,
            refund_amount: out.refund_amount
        });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Gửi đánh giá chuyến đi (Kích hoạt Trigger trg_reviews_after_insert)
exports.submitReview = async (req, res) => {
    try {
        const { booking_code, rating, comment } = req.body;
        const [rows] = await db.query(`
            SELECT b.booking_id, r.operator_id
            FROM bookings b
            JOIN tickets tk ON b.booking_id = tk.booking_id
            JOIN trips t ON tk.trip_id = t.trip_id
            JOIN routes r ON t.route_id = r.route_id
            WHERE b.booking_code = ? LIMIT 1
        `, [booking_code]);

        if (rows.length === 0) return res.json({ success: false, message: 'Mã vé không tồn tại!' });

        await db.query(
            'INSERT INTO reviews (booking_id, operator_id, user_id, rating, comment) VALUES (?, ?, 1, ?, ?)',
            [rows[0].booking_id, rows[0].operator_id, rating, comment]
        );
        res.json({ success: true, message: 'Cảm ơn đánh giá của bạn! Trigger DB đã tự động cập nhật điểm uy tín nhà xe.' });
    } catch (err) {
        res.status(400).json({ success: false, message: 'Đơn vé này đã được đánh giá trước đó hoặc lỗi dữ liệu.' });
    }
};
