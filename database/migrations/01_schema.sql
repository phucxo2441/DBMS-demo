-- ============================================================================
-- VEXETAU DBMS ARCHITECTURE - STEP 1: SCHEMA DEFINITION & CONSTRAINTS
-- Database: MySQL 8.0+
-- ============================================================================

CREATE DATABASE IF NOT EXISTS vexetau_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE vexetau_db;

-- 1. BẢNG PHÂN QUYỀN (RBAC)
CREATE TABLE roles (
    role_id INT AUTO_INCREMENT PRIMARY KEY,
    role_code VARCHAR(30) NOT NULL UNIQUE, -- CUSTOMER, OPERATOR, ADMIN
    role_name VARCHAR(100) NOT NULL,
    permissions JSON NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2. NGƯỜI DÙNG HỆ THỐNG
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    role_id INT NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    oauth_provider ENUM('LOCAL', 'GOOGLE', 'FACEBOOK') DEFAULT 'LOCAL',
    is_verified BOOLEAN DEFAULT TRUE,
    loyalty_points INT DEFAULT 0 CHECK (loyalty_points >= 0),
    status ENUM('ACTIVE', 'LOCKED') DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 3. DANH SÁCH HÀNH KHÁCH THƯỜNG DÙNG CỦA KHÁCH HÀNG
CREATE TABLE saved_passengers (
    saved_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    passenger_name VARCHAR(120) NOT NULL,
    passenger_phone VARCHAR(20) NOT NULL,
    id_card_number VARCHAR(30) NULL,
    passenger_type ENUM('ADULT', 'CHILD', 'ELDERLY') DEFAULT 'ADULT',
    CONSTRAINT fk_saved_pax_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 4. DANH MỤC TỈNH / THÀNH PHỐ
CREATE TABLE locations (
    location_id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    region ENUM('NORTH', 'CENTRAL', 'SOUTH') NOT NULL
) ENGINE=InnoDB;

-- 5. DANH MỤC BẾN XE / GA TÀU
CREATE TABLE stations (
    station_id INT AUTO_INCREMENT PRIMARY KEY,
    location_id INT NOT NULL,
    station_name VARCHAR(150) NOT NULL,
    station_type ENUM('BUS_STATION', 'TRAIN_STATION', 'PICKUP_POINT') NOT NULL,
    address VARCHAR(255) NOT NULL,
    latitude DECIMAL(10, 7) NULL,
    longitude DECIMAL(10, 7) NULL,
    CONSTRAINT fk_stations_location FOREIGN KEY (location_id) REFERENCES locations(location_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 6. NHÀ XE / ĐƠN VỊ VẬN HÀNH (ĐƯỜNG SẮT / XE KHÁCH)
CREATE TABLE operators (
    operator_id INT AUTO_INCREMENT PRIMARY KEY,
    owner_user_id INT NOT NULL,
    company_name VARCHAR(150) NOT NULL,
    tax_code VARCHAR(30) NOT NULL UNIQUE,
    hotline VARCHAR(20) NOT NULL,
    transport_category ENUM('BUS', 'TRAIN', 'BOTH') NOT NULL,
    commission_rate DECIMAL(5, 2) DEFAULT 8.00 CHECK (commission_rate BETWEEN 0 AND 50),
    rating_avg DECIMAL(3, 2) DEFAULT 5.00,
    total_reviews INT DEFAULT 0,
    approval_status ENUM('PENDING', 'APPROVED', 'SUSPENDED') DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_operators_owner FOREIGN KEY (owner_user_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 7. ĐỘI XE / ĐOÀN TÀU
CREATE TABLE vehicles (
    vehicle_id INT AUTO_INCREMENT PRIMARY KEY,
    operator_id INT NOT NULL,
    plate_or_train_code VARCHAR(50) NOT NULL UNIQUE,
    vehicle_type ENUM('LIMOUSINE_CABIN', 'SLEEPER_BUS', 'SEAT_BUS', 'EXPRESS_TRAIN') NOT NULL,
    seat_layout_config JSON NOT NULL, -- Cấu trúc tầng/toa/hàng/cột
    total_seats INT NOT NULL CHECK (total_seats > 0),
    amenities JSON NOT NULL,          -- ["Wifi", "Điều hòa", "Cổng sạc USB", "Chăn gối"]
    status ENUM('ACTIVE', 'MAINTENANCE') DEFAULT 'ACTIVE',
    CONSTRAINT fk_vehicles_operator FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 8. SƠ ĐỒ GHẾ / GIƯỜNG CHUẨN CỦA TỪNG XE / TÀU
CREATE TABLE vehicle_seats (
    v_seat_id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT NOT NULL,
    seat_code VARCHAR(15) NOT NULL,   -- VD: A01, B02, T1-G05
    coach_or_deck VARCHAR(30) NOT NULL, -- VD: Tầng 1, Tầng 2, Toa 1 VIP
    seat_tier ENUM('STANDARD', 'VIP', 'CABIN') DEFAULT 'STANDARD',
    price_multiplier DECIMAL(4, 2) DEFAULT 1.00,
    UNIQUE KEY uq_vehicle_seat (vehicle_id, seat_code),
    CONSTRAINT fk_vseats_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 9. NHÂN SỰ VẬN HÀNH (TÀI XẾ, LÁI TÀU, PHỤ XE)
CREATE TABLE staff (
    staff_id INT AUTO_INCREMENT PRIMARY KEY,
    operator_id INT NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    staff_role ENUM('DRIVER', 'TRAIN_CAPTAIN', 'ATTENDANT', 'TICKET_AGENT') NOT NULL,
    license_number VARCHAR(50) NULL,
    status ENUM('ACTIVE', 'OFF_DUTY') DEFAULT 'ACTIVE',
    CONSTRAINT fk_staff_operator FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 10. TUYẾN ĐƯỜNG / TUYẾN ĐƯỜNG SẮT
CREATE TABLE routes (
    route_id INT AUTO_INCREMENT PRIMARY KEY,
    operator_id INT NOT NULL,
    origin_location_id INT NOT NULL,
    destination_location_id INT NOT NULL,
    origin_station_id INT NOT NULL,
    destination_station_id INT NOT NULL,
    distance_km INT NOT NULL CHECK (distance_km > 0),
    estimated_duration_mins INT NOT NULL CHECK (estimated_duration_mins > 0),
    base_price DECIMAL(12, 2) NOT NULL CHECK (base_price >= 0),
    CONSTRAINT chk_different_locations CHECK (origin_location_id <> destination_location_id),
    CONSTRAINT fk_routes_operator FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE,
    CONSTRAINT fk_routes_orig_loc FOREIGN KEY (origin_location_id) REFERENCES locations(location_id),
    CONSTRAINT fk_routes_dest_loc FOREIGN KEY (destination_location_id) REFERENCES locations(location_id),
    CONSTRAINT fk_routes_orig_sta FOREIGN KEY (origin_station_id) REFERENCES stations(station_id),
    CONSTRAINT fk_routes_dest_sta FOREIGN KEY (destination_station_id) REFERENCES stations(station_id)
) ENGINE=InnoDB;

-- 11. CHUYẾN ĐI CỤ THỂ (TRIPS)
CREATE TABLE trips (
    trip_id INT AUTO_INCREMENT PRIMARY KEY,
    route_id INT NOT NULL,
    vehicle_id INT NOT NULL,
    driver_id INT NULL,
    departure_time DATETIME NOT NULL,
    arrival_time DATETIME NOT NULL,
    ticket_price DECIMAL(12, 2) NOT NULL CHECK (ticket_price >= 0),
    trip_status ENUM('SCHEDULED', 'BOARDING', 'DEPARTED', 'COMPLETED', 'CANCELLED') DEFAULT 'SCHEDULED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_trip_time CHECK (arrival_time > departure_time),
    CONSTRAINT fk_trips_route FOREIGN KEY (route_id) REFERENCES routes(route_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_driver FOREIGN KEY (driver_id) REFERENCES staff(staff_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 12. TRẠNG THÁI GHẾ THEO TỪNG CHUYẾN (BẢNG TRỌNG TÂM XỬ LÝ CONCURRENCY LOCKING)
CREATE TABLE trip_seats (
    trip_seat_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    trip_id INT NOT NULL,
    v_seat_id INT NOT NULL,
    seat_code VARCHAR(15) NOT NULL,
    coach_or_deck VARCHAR(30) NOT NULL,
    seat_tier ENUM('STANDARD', 'VIP', 'CABIN') DEFAULT 'STANDARD',
    final_price DECIMAL(12, 2) NOT NULL,
    seat_status ENUM('AVAILABLE', 'LOCKED', 'BOOKED') DEFAULT 'AVAILABLE',
    locked_by_session VARCHAR(100) NULL,
    lock_expires_at DATETIME NULL,
    version INT DEFAULT 1, -- Optimistic Lock Version
    UNIQUE KEY uq_trip_seat (trip_id, v_seat_id),
    UNIQUE KEY uq_trip_seat_code (trip_id, seat_code),
    UNIQUE KEY uq_trip_seat_trip_pair (trip_seat_id, trip_id),
    CONSTRAINT chk_trip_seat_lock_state CHECK (
        (seat_status = 'LOCKED' AND locked_by_session IS NOT NULL AND lock_expires_at IS NOT NULL)
        OR
        (seat_status <> 'LOCKED' AND locked_by_session IS NULL AND lock_expires_at IS NULL)
    ),
    CONSTRAINT fk_tripseats_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_tripseats_vseat FOREIGN KEY (v_seat_id) REFERENCES vehicle_seats(v_seat_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 13. CHÍNH SÁCH HỦY / ĐỔI VÉ & PHÍ DỊCH VỤ
CREATE TABLE cancellation_policies (
    policy_id INT AUTO_INCREMENT PRIMARY KEY,
    policy_name VARCHAR(100) NOT NULL,
    hours_before_departure INT NOT NULL,
    refund_percentage DECIMAL(5, 2) NOT NULL CHECK (refund_percentage BETWEEN 0 AND 100),
    description VARCHAR(255) NOT NULL
) ENGINE=InnoDB;

-- 14. MÃ GIẢM GIÁ / KHUYẾN MÃI
CREATE TABLE promotions (
    promo_id INT AUTO_INCREMENT PRIMARY KEY,
    operator_id INT NULL, -- NULL = Toàn sàn Admin phát hành; NOT NULL = Riêng của nhà xe
    promo_code VARCHAR(30) NOT NULL UNIQUE,
    discount_type ENUM('PERCENT', 'FIXED_AMOUNT') NOT NULL,
    discount_value DECIMAL(12, 2) NOT NULL CHECK (discount_value > 0),
    min_order_amount DECIMAL(12, 2) DEFAULT 0,
    max_discount_amount DECIMAL(12, 2) NULL,
    usage_limit INT DEFAULT 100,
    used_count INT DEFAULT 0,
    valid_from DATETIME NOT NULL,
    valid_to DATETIME NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT fk_promo_operator FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 15. ĐƠN ĐẶT VÉ (BOOKINGS)
CREATE TABLE bookings (
    booking_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_code VARCHAR(20) NOT NULL UNIQUE, -- VD: VXT-849201
    user_id INT NULL,
    contact_name VARCHAR(120) NOT NULL,
    contact_phone VARCHAR(20) NOT NULL,
    contact_email VARCHAR(150) NULL,
    promo_id INT NULL,
    points_used INT DEFAULT 0,
    subtotal_amount DECIMAL(12, 2) NOT NULL,
    discount_amount DECIMAL(12, 2) DEFAULT 0,
    service_fee DECIMAL(12, 2) DEFAULT 10000,
    total_amount DECIMAL(12, 2) NOT NULL,
    commission_amount DECIMAL(12, 2) DEFAULT 0,
    booking_status ENUM('PENDING_PAYMENT', 'CONFIRMED', 'CANCELLED', 'REFUNDED') DEFAULT 'PENDING_PAYMENT',
    booking_channel ENUM('WEB_APP', 'COUNTER_AGENT') DEFAULT 'WEB_APP',
    vat_invoice_requested BOOLEAN DEFAULT FALSE,
    vat_tax_code VARCHAR(30) NULL,
    vat_company_name VARCHAR(150) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookings_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT fk_bookings_promo FOREIGN KEY (promo_id) REFERENCES promotions(promo_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 16. VÉ ĐIỆN TỬ CHI TIẾT (TICKETS - MỖI GHẾ 1 VÉ & MÃ QR RIÊNG)
CREATE TABLE tickets (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_code VARCHAR(40) NOT NULL UNIQUE,
    booking_id INT NOT NULL,
    trip_id INT NOT NULL,
    trip_seat_id BIGINT NOT NULL UNIQUE,
    passenger_name VARCHAR(120) NOT NULL,
    passenger_phone VARCHAR(20) NOT NULL,
    pickup_point VARCHAR(200) NOT NULL,
    dropoff_point VARCHAR(200) NOT NULL,
    ticket_price DECIMAL(12, 2) NOT NULL,
    qr_payload VARCHAR(255) NOT NULL,
    checkin_status ENUM('NOT_CHECKED_IN', 'BOARDED', 'CANCELLED') DEFAULT 'NOT_CHECKED_IN',
    checked_in_at DATETIME NULL,
    CONSTRAINT fk_tickets_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_tickets_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tickets_tripseat_trip FOREIGN KEY (trip_seat_id, trip_id)
        REFERENCES trip_seats(trip_seat_id, trip_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 17. GIAO DỊCH THANH TOÁN & HOÀN TIỀN
CREATE TABLE payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT NOT NULL,
    transaction_ref VARCHAR(60) NOT NULL UNIQUE,
    payment_method ENUM('VNPAY', 'MOMO', 'ZALOPAY', 'BANK_QR', 'VISA_MASTER', 'CASH_COUNTER') NOT NULL,
    transaction_type ENUM('PAYMENT', 'REFUND') DEFAULT 'PAYMENT',
    amount DECIMAL(12, 2) NOT NULL,
    payment_status ENUM('PENDING', 'SUCCESS', 'FAILED') DEFAULT 'SUCCESS',
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payments_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 18. ĐÁNH GIÁ & PHẢN HỒI NHÀ XE
CREATE TABLE reviews (
    review_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT NOT NULL UNIQUE,
    operator_id INT NOT NULL,
    user_id INT NULL,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT NULL,
    operator_reply TEXT NULL,
    replied_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reviews_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT fk_reviews_operator FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 19. KHIẾU NẠI & TRANH CHẤP
CREATE TABLE complaints (
    complaint_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_code VARCHAR(20) NULL,
    customer_name VARCHAR(120) NOT NULL,
    customer_phone VARCHAR(20) NOT NULL,
    subject VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    status ENUM('OPEN', 'IN_PROGRESS', 'RESOLVED') DEFAULT 'OPEN',
    admin_resolution TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 20. TIN TỨC & BANNER QUẢNG CÁO
CREATE TABLE banners_news (
    item_id INT AUTO_INCREMENT PRIMARY KEY,
    item_type ENUM('BANNER', 'NEWS') NOT NULL,
    title VARCHAR(200) NOT NULL,
    summary VARCHAR(255) NOT NULL,
    badge_text VARCHAR(50) NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 21. THÔNG BÁO ĐẨY / SMS / EMAIL QUEUE
CREATE TABLE notifications (
    notif_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    recipient VARCHAR(150) NOT NULL,
    channel ENUM('EMAIL', 'SMS', 'PUSH') NOT NULL,
    title VARCHAR(150) NOT NULL,
    content TEXT NOT NULL,
    sent_status ENUM('SENT', 'QUEUED') DEFAULT 'SENT',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 22. NHẬT KÝ HOẠT ĐỘNG HỆ THỐNG (AUDIT LOGS - GHI TỰ ĐỘNG QUA TRIGGER)
CREATE TABLE audit_logs (
    log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(60) NOT NULL,
    record_id VARCHAR(50) NOT NULL,
    action_type ENUM('INSERT', 'UPDATE', 'DELETE', 'LOCK_SEAT', 'AUTO_RELEASE', 'CHECKIN') NOT NULL,
    actor_info VARCHAR(120) DEFAULT 'SYSTEM_DB_TRIGGER',
    old_values JSON NULL,
    new_values JSON NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
