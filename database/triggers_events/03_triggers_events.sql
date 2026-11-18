-- ============================================================================
-- VEXETAU DBMS ARCHITECTURE - STEP 3: TRIGGERS & SCHEDULED EVENTS
-- ============================================================================
USE vexetau_db;

DELIMITER $$

-- 1. TRIGGER TỰ ĐỘNG GHI AUDIT LOG KHI ĐƠN ĐẶT VÉ THAY ĐỔI TRẠNG THÁI
CREATE TRIGGER trg_bookings_after_update_audit
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF OLD.booking_status <> NEW.booking_status THEN
        INSERT INTO audit_logs (table_name, record_id, action_type, actor_info, old_values, new_values)
        VALUES (
            'bookings',
            NEW.booking_code,
            'UPDATE',
            'DB_TRIGGER_AUDIT',
            JSON_OBJECT('booking_status', OLD.booking_status, 'total_amount', OLD.total_amount),
            JSON_OBJECT('booking_status', NEW.booking_status, 'total_amount', NEW.total_amount)
        );
    END IF;
END$$

-- 2. TRIGGER TỰ ĐỘNG CẬP NHẬT ĐIỂM ĐÁNH GIÁ TRUNG BÌNH CỦA NHÀ XE
CREATE TRIGGER trg_reviews_after_insert
AFTER INSERT ON reviews
FOR EACH ROW
BEGIN
    UPDATE operators
    SET rating_avg = (
            SELECT ROUND(AVG(rating), 2)
            FROM reviews
            WHERE operator_id = NEW.operator_id
        ),
        total_reviews = (
            SELECT COUNT(*)
            FROM reviews
            WHERE operator_id = NEW.operator_id
        )
    WHERE operator_id = NEW.operator_id;
END$$

-- 3. SCHEDULED EVENT: TỰ ĐỘNG NHẢ GHẾ HẾT HẠN GIỮ CHỖ MỖI 10 GIÂY
-- Bật event_scheduler bằng cấu hình server; không đổi biến GLOBAL trong migration
-- vì thao tác đó cần quyền quản trị và không tồn tại sau khi MySQL khởi động lại.
CREATE EVENT IF NOT EXISTS evt_auto_release_expired_seats
ON SCHEDULE EVERY 10 SECOND
ON COMPLETION PRESERVE
DO
BEGIN
    DECLARE v_released_count INT DEFAULT 0;

    SELECT COUNT(*) INTO v_released_count
    FROM trip_seats
    WHERE seat_status = 'LOCKED' AND lock_expires_at <= NOW();

    IF v_released_count > 0 THEN
        UPDATE trip_seats
        SET seat_status = 'AVAILABLE',
            locked_by_session = NULL,
            lock_expires_at = NULL,
            version = version + 1
        WHERE seat_status = 'LOCKED' AND lock_expires_at <= NOW();

        INSERT INTO audit_logs (table_name, record_id, action_type, actor_info, new_values)
        VALUES ('trip_seats', 'BATCH', 'AUTO_RELEASE', 'MYSQL_EVENT_SCHEDULER',
                JSON_OBJECT('released_seats_count', v_released_count, 'executed_at', NOW()));
    END IF;
END$$

DELIMITER ;
