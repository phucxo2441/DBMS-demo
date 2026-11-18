-- ============================================================================
-- VEXETAU DBMS ARCHITECTURE - STEP 2: STORED PROCEDURES & ACID TRANSACTIONS
-- ============================================================================
USE vexetau_db;

DELIMITER $$

-- ----------------------------------------------------------------------------
-- PROCEDURE 1: KHÓA GHẾ TẠM THỜI VỚI PESSIMISTIC LOCKING (SELECT ... FOR UPDATE)
-- Ngăn chặn triệt để Race Condition khi 2 khách bấm giữ cùng 1 ghế cùng mili-giây
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_HoldSeatWithLock(
    IN p_trip_id INT,
    IN p_seat_code VARCHAR(15),
    IN p_session_id VARCHAR(100),
    IN p_hold_seconds INT,
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255),
    OUT p_expires_at DATETIME
)
BEGIN
    DECLARE v_seat_status VARCHAR(20);
    DECLARE v_locked_by VARCHAR(100);
    DECLARE v_lock_exp DATETIME;
    DECLARE v_trip_seat_id BIGINT;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_trip_seat_id = NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Lỗi Transaction DB khi khóa ghế (Rollback đã kích hoạt).';
    END;

    SET p_success = FALSE;
    SET p_expires_at = NULL;
    IF p_session_id IS NULL OR TRIM(p_session_id) = ''
       OR p_hold_seconds IS NULL OR p_hold_seconds NOT BETWEEN 30 AND 600 THEN
        SET p_message = 'Phiên giữ ghế hoặc thời gian giữ chỗ không hợp lệ.';
    ELSE
    START TRANSACTION;

    -- Khóa dòng dữ liệu ghế ở mức Row-Level Lock
    SELECT trip_seat_id, seat_status, locked_by_session, lock_expires_at
    INTO v_trip_seat_id, v_seat_status, v_locked_by, v_lock_exp
    FROM trip_seats
    WHERE trip_id = p_trip_id AND seat_code = p_seat_code
    FOR UPDATE;

    IF v_trip_seat_id IS NULL THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Không tìm thấy mã ghế trên chuyến này.';
    ELSEIF v_seat_status = 'BOOKED' THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = CONCAT('Ghế ', p_seat_code, ' đã có người thanh toán thành công!');
    ELSEIF v_seat_status = 'LOCKED' AND v_lock_exp > NOW() AND v_locked_by <> p_session_id THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = CONCAT('Xung đột đồng thời: Ghế ', p_seat_code, ' đang được khách hàng khác giữ chỗ!');
    ELSE
        SET p_expires_at = DATE_ADD(NOW(), INTERVAL p_hold_seconds SECOND);

        UPDATE trip_seats
        SET seat_status = 'LOCKED',
            locked_by_session = p_session_id,
            lock_expires_at = p_expires_at,
            version = version + 1
        WHERE trip_seat_id = v_trip_seat_id;

        INSERT INTO audit_logs(table_name, record_id, action_type, actor_info, new_values)
        VALUES ('trip_seats', v_trip_seat_id, 'LOCK_SEAT', p_session_id,
                JSON_OBJECT('trip_id', p_trip_id, 'seat_code', p_seat_code, 'expires_at', p_expires_at));

        COMMIT;
        SET p_success = TRUE;
        SET p_message = CONCAT('Đã khóa giữ ghế ', p_seat_code, ' thành công trong ', p_hold_seconds, ' giây.');
    END IF;
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- PROCEDURE 2: NHẢ GHẾ THỦ CÔNG KHI KHÁCH BỎ CHỌN
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_ReleaseSeat(
    IN p_trip_id INT,
    IN p_seat_code VARCHAR(15),
    IN p_session_id VARCHAR(100)
)
BEGIN
    UPDATE trip_seats
    SET seat_status = 'AVAILABLE',
        locked_by_session = NULL,
        lock_expires_at = NULL,
        version = version + 1
    WHERE trip_id = p_trip_id
      AND seat_code = p_seat_code
      AND seat_status = 'LOCKED'
      AND locked_by_session = p_session_id;
END$$

-- ----------------------------------------------------------------------------
-- PROCEDURE 3: XÁC NHẬN ĐẶT VÉ, THANH TOÁN, ÁP MÃ GIẢM GIÁ & XUẤT VÉ ĐIỆN TỬ QR
-- Toàn bộ quy trình chạy trong 1 ACID Transaction duy nhất
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_ConfirmBookingAndPay(
    IN p_user_id INT,
    IN p_session_id VARCHAR(100),
    IN p_trip_id INT,
    IN p_seat_codes_csv VARCHAR(255), -- VD: 'A01,A02'
    IN p_contact_name VARCHAR(120),
    IN p_contact_phone VARCHAR(20),
    IN p_contact_email VARCHAR(150),
    IN p_pickup_point VARCHAR(200),
    IN p_dropoff_point VARCHAR(200),
    IN p_promo_code VARCHAR(30),
    IN p_use_points INT,
    IN p_payment_method VARCHAR(30),
    IN p_booking_channel VARCHAR(30),
    IN p_vat_requested BOOLEAN,
    IN p_vat_tax_code VARCHAR(30),
    IN p_vat_company VARCHAR(150),
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255),
    OUT p_booking_code VARCHAR(20)
)
BEGIN
    DECLARE v_subtotal DECIMAL(12,2) DEFAULT 0;
    DECLARE v_discount DECIMAL(12,2) DEFAULT 0;
    DECLARE v_service_fee DECIMAL(12,2) DEFAULT 10000;
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;
    DECLARE v_commission_rate DECIMAL(5,2) DEFAULT 8.00;
    DECLARE v_commission_amt DECIMAL(12,2) DEFAULT 0;
    DECLARE v_promo_id INT DEFAULT NULL;
    DECLARE v_discount_type VARCHAR(20);
    DECLARE v_discount_val DECIMAL(12,2);
    DECLARE v_max_discount DECIMAL(12,2);
    DECLARE v_promo_operator_id INT;
    DECLARE v_promo_min_order DECIMAL(12,2);
    DECLARE v_promo_usage_limit INT;
    DECLARE v_promo_used_count INT;
    DECLARE v_promo_valid_from DATETIME;
    DECLARE v_promo_valid_to DATETIME;
    DECLARE v_promo_active BOOLEAN;
    DECLARE v_booking_id INT;
    DECLARE v_seat_count INT DEFAULT 0;
    DECLARE v_valid_locked_count INT DEFAULT 0;
    DECLARE v_user_points INT DEFAULT 0;
    DECLARE v_points_used INT DEFAULT 0;
    DECLARE v_operator_id INT DEFAULT NULL;
    DECLARE v_not_found BOOLEAN DEFAULT FALSE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Giao dịch thanh toán thất bại do lỗi toàn vẹn dữ liệu (Rollback).';
    END;

    SET p_success = FALSE;
    SET p_booking_code = NULL;
    SET v_points_used = COALESCE(p_use_points, 0);
    IF p_trip_id IS NULL OR p_session_id IS NULL OR TRIM(p_session_id) = ''
       OR p_seat_codes_csv IS NULL OR TRIM(p_seat_codes_csv) = ''
       OR v_points_used < 0 OR p_contact_name IS NULL OR TRIM(p_contact_name) = ''
       OR p_contact_phone IS NULL OR TRIM(p_contact_phone) = '' THEN
        SET p_message = 'Thông tin đặt vé không hợp lệ.';
    ELSE
    START TRANSACTION;

    -- 1. Chỉ thanh toán ghế còn hiệu lực giữ bởi đúng phiên hiện tại.
    SET v_seat_count = LENGTH(p_seat_codes_csv) - LENGTH(REPLACE(p_seat_codes_csv, ',', '')) + 1;

    SELECT COUNT(*), COALESCE(SUM(final_price), 0)
    INTO v_valid_locked_count, v_subtotal
    FROM trip_seats
    WHERE trip_id = p_trip_id
      AND FIND_IN_SET(seat_code, p_seat_codes_csv) > 0
      AND seat_status = 'LOCKED'
      AND locked_by_session = p_session_id
      AND lock_expires_at > NOW()
    FOR UPDATE;

    IF v_valid_locked_count < v_seat_count THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Một hoặc nhiều ghế đã hết thời gian giữ chỗ hoặc đã bị đặt trước!';
    ELSE
        SELECT o.commission_rate, o.operator_id
        INTO v_commission_rate, v_operator_id
        FROM trips t
        JOIN routes r ON t.route_id = r.route_id
        JOIN operators o ON r.operator_id = o.operator_id
        WHERE t.trip_id = p_trip_id
          AND t.trip_status = 'SCHEDULED'
          AND t.departure_time > NOW()
        FOR UPDATE;

        IF v_not_found THEN
            ROLLBACK;
            SET p_success = FALSE;
            SET p_message = 'Chuyến đi không tồn tại, đã khởi hành hoặc không còn mở bán.';
        ELSE
        -- 2. Kiểm tra mã khuyến mãi (nếu có)
        IF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
            SET v_not_found = FALSE;
            SELECT promo_id, discount_type, discount_value, max_discount_amount,
                   operator_id, min_order_amount, usage_limit, used_count, valid_from, valid_to, is_active
            INTO v_promo_id, v_discount_type, v_discount_val, v_max_discount,
                 v_promo_operator_id, v_promo_min_order, v_promo_usage_limit, v_promo_used_count,
                 v_promo_valid_from, v_promo_valid_to, v_promo_active
            FROM promotions
            WHERE promo_code = p_promo_code
            FOR UPDATE;

            IF NOT v_not_found
               AND v_promo_active = TRUE
               AND v_promo_used_count < v_promo_usage_limit
               AND NOW() BETWEEN v_promo_valid_from AND v_promo_valid_to
               AND v_subtotal >= v_promo_min_order
               AND (v_promo_operator_id IS NULL OR v_promo_operator_id = v_operator_id) THEN
                IF v_discount_type = 'PERCENT' THEN
                    SET v_discount = v_subtotal * (v_discount_val / 100);
                    IF v_max_discount IS NOT NULL AND v_discount > v_max_discount THEN
                        SET v_discount = v_max_discount;
                    END IF;
                ELSE
                    SET v_discount = LEAST(v_discount_val, v_subtotal);
                END IF;
                SET v_discount = LEAST(v_discount, v_subtotal);

                UPDATE promotions SET used_count = used_count + 1 WHERE promo_id = v_promo_id;
            ELSE
                SET v_promo_id = NULL;
            END IF;
        END IF;

        -- 3. Điểm chỉ được trừ khi tài khoản đủ số dư; 1 điểm = 1.000 VNĐ.
        IF v_points_used > 0 THEN
            IF p_user_id IS NULL THEN
                ROLLBACK;
                SET p_success = FALSE;
                SET p_message = 'Cần đăng nhập để sử dụng điểm thưởng.';
            ELSE
                SET v_not_found = FALSE;
                SELECT loyalty_points INTO v_user_points
                FROM users
                WHERE user_id = p_user_id
                FOR UPDATE;

                IF v_not_found OR v_user_points < v_points_used THEN
                    ROLLBACK;
                    SET p_success = FALSE;
                    SET p_message = 'Số dư điểm thưởng không đủ.';
                ELSE
                    SET v_points_used = LEAST(v_points_used, FLOOR(GREATEST(0, v_subtotal - v_discount) / 1000));
                    SET v_discount = v_discount + (v_points_used * 1000);
                    UPDATE users
                    SET loyalty_points = loyalty_points - v_points_used
                    WHERE user_id = p_user_id;
                END IF;
            END IF;
        END IF;

        IF p_success = FALSE AND p_message IS NOT NULL THEN
            ROLLBACK;
        ELSE
            IF p_booking_channel = 'COUNTER_AGENT' THEN
                SET v_service_fee = 0;
            END IF;

            SET v_total = GREATEST(0, v_subtotal - v_discount + v_service_fee);

            SET v_commission_amt = v_subtotal * (v_commission_rate / 100);
            SET p_booking_code = CONCAT('VXT-', UPPER(LEFT(REPLACE(UUID(), '-', ''), 16)));

            -- 4. Tạo đơn đặt vé (bookings)
            INSERT INTO bookings (
                booking_code, user_id, contact_name, contact_phone, contact_email,
                promo_id, points_used, subtotal_amount, discount_amount, service_fee,
                total_amount, commission_amount, booking_status, booking_channel,
                vat_invoice_requested, vat_tax_code, vat_company_name
            ) VALUES (
                p_booking_code, p_user_id, p_contact_name, p_contact_phone, p_contact_email,
                v_promo_id, v_points_used, v_subtotal, v_discount, v_service_fee,
                v_total, v_commission_amt, 'CONFIRMED', COALESCE(p_booking_channel, 'WEB_APP'),
                COALESCE(p_vat_requested, FALSE), p_vat_tax_code, p_vat_company
            );

            SET v_booking_id = LAST_INSERT_ID();

            -- 5. Xuất vé điện tử QR cho từng ghế
            INSERT INTO tickets (
                ticket_code, booking_id, trip_id, trip_seat_id,
                passenger_name, passenger_phone, pickup_point, dropoff_point,
                ticket_price, qr_payload
            )
            SELECT
                CONCAT('TK-', RIGHT(p_booking_code, 12), '-', seat_code),
                v_booking_id,
                p_trip_id,
                trip_seat_id,
                p_contact_name,
                p_contact_phone,
                p_pickup_point,
                p_dropoff_point,
                final_price,
                CONCAT('VEXETAU|', p_booking_code, '|TRIP:', p_trip_id, '|SEAT:', seat_code)
            FROM trip_seats
            WHERE trip_id = p_trip_id
              AND FIND_IN_SET(seat_code, p_seat_codes_csv) > 0
              AND seat_status = 'LOCKED'
              AND locked_by_session = p_session_id
              AND lock_expires_at > NOW();

            -- 6. Cập nhật trạng thái ghế sang BOOKED
            UPDATE trip_seats
            SET seat_status = 'BOOKED',
                locked_by_session = NULL,
                lock_expires_at = NULL,
                version = version + 1
            WHERE trip_id = p_trip_id
              AND FIND_IN_SET(seat_code, p_seat_codes_csv) > 0
              AND seat_status = 'LOCKED'
              AND locked_by_session = p_session_id
              AND lock_expires_at > NOW();

            -- 7. Ghi nhận thanh toán
            INSERT INTO payments (booking_id, transaction_ref, payment_method, transaction_type, amount, payment_status)
            VALUES (v_booking_id, CONCAT('PAY-', REPLACE(UUID(), '-', '')), p_payment_method, 'PAYMENT', v_total, 'SUCCESS');

            -- 8. Cộng điểm thưởng cho khách hàng (1 điểm / 20.000 VNĐ)
            IF p_user_id IS NOT NULL THEN
                UPDATE users SET loyalty_points = loyalty_points + FLOOR(v_total / 20000) WHERE user_id = p_user_id;
            END IF;

            -- 9. Đẩy thông báo xác nhận vé điện tử vào hàng đợi
            INSERT INTO notifications (user_id, recipient, channel, title, content)
            VALUES (
                p_user_id,
                COALESCE(p_contact_email, p_contact_phone),
                'EMAIL',
                CONCAT('Vé điện tử VEXETAU #', p_booking_code),
                CONCAT('Đặt vé thành công! Mã đặt chỗ: ', p_booking_code, '. Ghế: ', p_seat_codes_csv, '. Tổng thanh toán: ', FORMAT(v_total, 0), 'đ.')
            );

            COMMIT;
            SET p_success = TRUE;
            SET p_message = 'Đặt vé và thanh toán thành công! Vé điện tử QR đã được phát hành.';
        END IF;
        END IF;
    END IF;
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- PROCEDURE 4: HỦY VÉ & HOÀN TIỀN TỰ ĐỘNG THEO CHÍNH SÁCH THỜI GIAN
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_CancelBookingAndRefund(
    IN p_booking_code VARCHAR(20),
    IN p_phone VARCHAR(20),
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255),
    OUT p_refund_amount DECIMAL(12,2)
)
BEGIN
    DECLARE v_booking_id INT;
    DECLARE v_status VARCHAR(30);
    DECLARE v_subtotal DECIMAL(12,2);
    DECLARE v_discount DECIMAL(12,2);
    DECLARE v_dep_time DATETIME;
    DECLARE v_hours_left INT;
    DECLARE v_refund_pct DECIMAL(5,2) DEFAULT 0;
    DECLARE v_has_boarded BOOLEAN DEFAULT FALSE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_booking_id = NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Lỗi hệ thống khi xử lý hoàn hủy vé.';
    END;

    SET p_success = FALSE;
    SET p_refund_amount = NULL;
    START TRANSACTION;

    SELECT b.booking_id, b.booking_status, b.subtotal_amount, b.discount_amount,
           MIN(t.departure_time), MAX(tk.checkin_status = 'BOARDED')
    INTO v_booking_id, v_status, v_subtotal, v_discount, v_dep_time, v_has_boarded
    FROM bookings b
    JOIN tickets tk ON b.booking_id = tk.booking_id
    JOIN trips t ON tk.trip_id = t.trip_id
    WHERE b.booking_code = p_booking_code AND b.contact_phone = p_phone
    GROUP BY b.booking_id, b.booking_status, b.subtotal_amount, b.discount_amount
    FOR UPDATE;

    IF v_booking_id IS NULL THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Không tìm thấy đơn đặt vé khớp với Mã vé và SĐT.';
    ELSEIF v_status <> 'CONFIRMED' THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = CONCAT('Đơn vé hiện ở trạng thái ', v_status, ', không thể hủy.');
    ELSEIF v_dep_time <= NOW() OR v_has_boarded THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Không thể hủy vé sau giờ khởi hành hoặc sau khi đã soát vé.';
    ELSE
        SET v_hours_left = TIMESTAMPDIFF(HOUR, NOW(), v_dep_time);

        -- Tra cứu bảng chính sách hủy vé (cancellation_policies)
        SELECT COALESCE(MAX(refund_percentage), 0)
        INTO v_refund_pct
        FROM cancellation_policies
        WHERE v_hours_left >= hours_before_departure;

        SET p_refund_amount = GREATEST(0, v_subtotal - v_discount) * (v_refund_pct / 100);

        -- Cập nhật trạng thái booking & tickets
        UPDATE bookings SET booking_status = 'REFUNDED' WHERE booking_id = v_booking_id;
        UPDATE tickets SET checkin_status = 'CANCELLED' WHERE booking_id = v_booking_id;

        -- Nhả ghế trên chuyến về AVAILABLE
        UPDATE trip_seats ts
        JOIN tickets tk ON ts.trip_seat_id = tk.trip_seat_id
        SET ts.seat_status = 'AVAILABLE',
            ts.version = ts.version + 1
        WHERE tk.booking_id = v_booking_id
          AND ts.seat_status = 'BOOKED';

        -- Tạo giao dịch hoàn tiền
        IF p_refund_amount > 0 THEN
            INSERT INTO payments (booking_id, transaction_ref, payment_method, transaction_type, amount, payment_status)
            VALUES (v_booking_id, CONCAT('REF-', REPLACE(UUID(), '-', '')), 'BANK_QR', 'REFUND', p_refund_amount, 'SUCCESS');
        END IF;

        COMMIT;
        SET p_success = TRUE;
        SET p_message = CONCAT('Hủy vé thành công! Mức hoàn áp dụng: ', v_refund_pct, '% (', FORMAT(p_refund_amount, 0), 'đ).');
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- PROCEDURE 5: NHÀ XE SOÁT VÉ BẰNG MÃ QR KHI LÊN XE / TÀU
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_OperatorCheckInQR(
    IN p_ticket_code VARCHAR(40),
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_ticket_id INT;
    DECLARE v_checkin_status VARCHAR(30);
    DECLARE v_pax_name VARCHAR(120);
    DECLARE v_seat_code VARCHAR(15);

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_ticket_id = NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'Lỗi hệ thống khi soát vé; giao dịch đã được hoàn tác.';
    END;

    SET p_success = FALSE;
    IF p_ticket_code IS NULL OR TRIM(p_ticket_code) = '' THEN
        SET p_message = 'Mã QR không được để trống.';
    ELSE
    START TRANSACTION;

    SELECT tk.ticket_id, tk.checkin_status, tk.passenger_name, ts.seat_code
    INTO v_ticket_id, v_checkin_status, v_pax_name, v_seat_code
    FROM tickets tk
    JOIN trip_seats ts ON tk.trip_seat_id = ts.trip_seat_id
    JOIN bookings b ON tk.booking_id = b.booking_id
    WHERE (tk.ticket_code = p_ticket_code OR tk.qr_payload = p_ticket_code)
      AND b.booking_status = 'CONFIRMED'
    LIMIT 1
    FOR UPDATE;

    IF v_ticket_id IS NULL THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'MÃ QR KHÔNG HỢP LỆ: Không tìm thấy vé đã thanh toán!';
    ELSEIF v_checkin_status = 'CANCELLED' THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = 'CẢNH BÁO: Vé này đã bị hủy trước đó!';
    ELSEIF v_checkin_status = 'BOARDED' THEN
        ROLLBACK;
        SET p_success = FALSE;
        SET p_message = CONCAT('CẢNH BÁO TRÙNG VÉ: Hành khách ', v_pax_name, ' (Ghế ', v_seat_code, ') đã soát vé lên xe trước đó!');
    ELSE
        UPDATE tickets
        SET checkin_status = 'BOARDED',
            checked_in_at = NOW()
        WHERE ticket_id = v_ticket_id;

        INSERT INTO audit_logs(table_name, record_id, action_type, actor_info, new_values)
        VALUES ('tickets', v_ticket_id, 'CHECKIN', 'OPERATOR_QR_SCANNER',
                JSON_OBJECT('ticket_code', p_ticket_code, 'passenger', v_pax_name, 'seat', v_seat_code));

        COMMIT;
        SET p_success = TRUE;
        SET p_message = CONCAT('HỢP LỆ ✔ Hành khách: ', v_pax_name, ' — Ghế/Giường: ', v_seat_code);
    END IF;
    END IF;
END$$

DELIMITER ;
