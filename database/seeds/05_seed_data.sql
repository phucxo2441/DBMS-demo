-- ============================================================================
-- VEXETAU DBMS ARCHITECTURE - STEP 5: SEED DATA (VIETNAM TRANSPORT DATA)
-- ============================================================================
USE vexetau_db;

-- 1. ROLES (RBAC)
INSERT INTO roles (role_code, role_name, permissions) VALUES
('CUSTOMER', 'Khách hàng đặt vé', '["SEARCH_TRIP", "BOOK_TICKET", "CANCEL_TICKET", "REVIEW"]'),
('OPERATOR', 'Nhà xe / Đơn vị đường sắt', '["MANAGE_FLEET", "MANAGE_TRIPS", "SCAN_QR", "VIEW_REVENUE"]'),
('ADMIN', 'Quản trị viên hệ thống', '["ALL_ACCESS", "APPROVE_OPERATOR", "SYSTEM_CONFIG", "VIEW_AUDIT_LOGS"]');

-- 2. USERS
INSERT INTO users (role_id, full_name, email, phone, password_hash, oauth_provider, loyalty_points) VALUES
(1, 'Nguyễn Minh Khoa', 'khoa.nguyen@gmail.com', '0901234567', '$2b$10$demoHashCustomer123', 'GOOGLE', 120),
(1, 'Trần Thu Hà', 'ha.tran@gmail.com', '0912345678', '$2b$10$demoHashCustomer456', 'LOCAL', 45),
(2, 'Quản lý Phương Trang FUTA', 'ops@futabus.vn', '19006067', '$2b$10$demoHashOperator1', 'LOCAL', 0),
(2, 'Điều hành Đường Sắt Việt Nam (DSVN)', 'ops@dsvn.vn', '19000109', '$2b$10$demoHashOperator2', 'LOCAL', 0),
(2, 'Quản lý Sao Việt Limousine', 'ops@saoviet.vn', '19006746', '$2b$10$demoHashOperator3', 'LOCAL', 0),
(3, 'Admin Hệ Thống VEXETAU', 'admin@vexetau.vn', '0988888888', '$2b$10$demoHashAdmin999', 'LOCAL', 0);

-- 3. SAVED PASSENGERS
INSERT INTO saved_passengers (user_id, passenger_name, passenger_phone, id_card_number, passenger_type) VALUES
(1, 'Nguyễn Minh Khoa', '0901234567', '079095001234', 'ADULT'),
(1, 'Nguyễn Thảo Vy', '0909888777', '079198005678', 'ADULT');

-- 4. LOCATIONS
INSERT INTO locations (code, name, region) VALUES
('SGN', 'TP. Hồ Chí Minh', 'SOUTH'),
('DLI', 'Đà Lạt (Lâm Đồng)', 'CENTRAL'),
('NHA', 'Nha Trang (Khánh Hòa)', 'CENTRAL'),
('HAN', 'Hà Nội', 'NORTH'),
('SAP', 'Sa Pa (Lào Cai)', 'NORTH'),
('DAD', 'Đà Nẵng', 'CENTRAL');

-- 5. STATIONS
INSERT INTO stations (location_id, station_name, station_type, address, latitude, longitude) VALUES
(1, 'Bến xe Miền Đông Mới', 'BUS_STATION', '501 Hoàng Hữu Nam, TP. Thủ Đức, TP.HCM', 10.8794000, 106.8142000),
(1, 'Ga Sài Gòn', 'TRAIN_STATION', '01 Nguyễn Thông, Quận 3, TP.HCM', 10.7826000, 106.6768000),
(2, 'Bến xe Liên tỉnh Đà Lạt', 'BUS_STATION', '01 Tô Hiến Thành, Phường 3, Đà Lạt', 11.9304000, 108.4452000),
(3, 'Ga Nha Trang', 'TRAIN_STATION', '17 Thái Nguyên, Phước Tân, Nha Trang', 12.2483000, 109.1829000),
(3, 'Bến xe Phía Nam Nha Trang', 'BUS_STATION', 'Km6 Đường 23/10, Nha Trang', 12.2461000, 109.1422000),
(4, 'Bến xe Mỹ Đình', 'BUS_STATION', '20 Phạm Hùng, Nam Từ Liêm, Hà Nội', 21.0285000, 105.7782000),
(4, 'Ga Hà Nội', 'TRAIN_STATION', '120 Lê Duẩn, Hoàn Kiếm, Hà Nội', 21.0245000, 105.8412000),
(5, 'Bến xe Sa Pa', 'BUS_STATION', 'Đường N1, Thị xã Sa Pa, Lào Cai', 22.3402000, 103.8448000),
(6, 'Ga Đà Nẵng', 'TRAIN_STATION', '791 Hải Phòng, Thanh Khê, Đà Nẵng', 16.0718000, 108.2097000);

-- 6. OPERATORS
INSERT INTO operators (owner_user_id, company_name, tax_code, hotline, transport_category, commission_rate, rating_avg, total_reviews, approval_status) VALUES
(3, 'Phương Trang - FUTA Bus Lines', '0303123456', '1900 6067', 'BUS', 8.00, 4.85, 1420, 'APPROVED'),
(4, 'Đường Sắt Việt Nam (VNR - Tàu SE)', '0100105052', '1900 0109', 'TRAIN', 6.50, 4.70, 980, 'APPROVED'),
(5, 'Sao Việt Limousine', '0105987654', '1900 6746', 'BUS', 9.00, 4.90, 860, 'APPROVED'),
(3, 'Nhà xe Hoàng Long Express (Chờ duyệt)', '0200456789', '1900 9889', 'BUS', 8.50, 5.00, 0, 'PENDING');

-- 7. VEHICLES
INSERT INTO vehicles (operator_id, plate_or_train_code, vehicle_type, seat_layout_config, total_seats, amenities) VALUES
(1, '51B-298.45', 'LIMOUSINE_CABIN', '{"decks": 2, "cols": 2, "rows": 6}', 24, '["Cabin riêng tư", "Wifi 5G", "Màn hình giải trí", "Cổng sạc Type-C", "Nước suối"]'),
(1, '51B-412.88', 'SLEEPER_BUS', '{"decks": 2, "cols": 3, "rows": 6}', 36, '["Giường nằm bọc da", "Wifi", "Điều hòa", "Chăn gối sạch"]'),
(2, 'TÀU-SE2-VIP', 'EXPRESS_TRAIN', '{"coaches": 2, "cabins_per_coach": 4, "berths": 4}', 32, '["Khoang 4 giường điều hòa", "Toa nhà hàng", "Ổ cắm điện", "Ngắm cảnh biển"]'),
(3, '29B-608.99', 'LIMOUSINE_CABIN', '{"decks": 2, "cols": 2, "rows": 6}', 24, '["Cung điện di động", "Massage lưng", "Wifi tốc độ cao", "Khăn lạnh"]');

-- 8. GENERATE VEHICLE SEATS FOR EACH VEHICLE
-- Xe 1 (24 Cabin: A01..A12 Tầng 1, B01..B12 Tầng 2)
INSERT INTO vehicle_seats (vehicle_id, seat_code, coach_or_deck, seat_tier, price_multiplier)
SELECT 1, CONCAT('A', LPAD(n, 2, '0')), 'Tầng 1 (Cabin)', 'CABIN', 1.00
FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12) nums
UNION ALL
SELECT 1, CONCAT('B', LPAD(n, 2, '0')), 'Tầng 2 (Cabin)', 'CABIN', 1.00
FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12) nums;

-- Xe 2 (36 Giường nằm)
INSERT INTO vehicle_seats (vehicle_id, seat_code, coach_or_deck, seat_tier, price_multiplier)
SELECT 2, CONCAT('G', LPAD(n, 2, '0')), IF(n <= 18, 'Tầng 1', 'Tầng 2'), 'STANDARD', 1.00
FROM (
    SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6
    UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
    UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16 UNION SELECT 17 UNION SELECT 18
    UNION SELECT 19 UNION SELECT 20 UNION SELECT 21 UNION SELECT 22 UNION SELECT 23 UNION SELECT 24
    UNION SELECT 25 UNION SELECT 26 UNION SELECT 27 UNION SELECT 28 UNION SELECT 29 UNION SELECT 30
    UNION SELECT 31 UNION SELECT 32 UNION SELECT 33 UNION SELECT 34 UNION SELECT 35 UNION SELECT 36
) nums;

-- Tàu SE2 (32 Giường khoang VIP Toa 1 & Toa 2)
INSERT INTO vehicle_seats (vehicle_id, seat_code, coach_or_deck, seat_tier, price_multiplier)
SELECT 3, CONCAT('T1-G', LPAD(n, 2, '0')), 'Toa 1 (Khoang 4 VIP)', 'VIP', 1.15
FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16) nums
UNION ALL
SELECT 3, CONCAT('T2-G', LPAD(n, 2, '0')), 'Toa 2 (Khoang 4 VIP)', 'VIP', 1.00
FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16) nums;

-- Xe 4 (24 Cabin Sao Việt)
INSERT INTO vehicle_seats (vehicle_id, seat_code, coach_or_deck, seat_tier, price_multiplier)
SELECT 4, CONCAT('C', LPAD(n, 2, '0')), IF(n <= 12, 'Tầng 1', 'Tầng 2'), 'CABIN', 1.00
FROM (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16 UNION SELECT 17 UNION SELECT 18 UNION SELECT 19 UNION SELECT 20 UNION SELECT 21 UNION SELECT 22 UNION SELECT 23 UNION SELECT 24) nums;

-- 9. STAFF
INSERT INTO staff (operator_id, full_name, phone, staff_role, license_number) VALUES
(1, 'Lê Văn Hùng', '0903111222', 'DRIVER', 'FC-79012345'),
(2, 'Trần Quốc Bảo (Trưởng tàu SE2)', '0904333444', 'TRAIN_CAPTAIN', 'DSVN-8821'),
(3, 'Phạm Đức Mạnh', '0905666777', 'DRIVER', 'FC-29098765');

-- 10. ROUTES
INSERT INTO routes (operator_id, origin_location_id, destination_location_id, origin_station_id, destination_station_id, distance_km, estimated_duration_mins, base_price) VALUES
(1, 1, 2, 1, 3, 305, 390, 340000),  -- TP.HCM -> Đà Lạt (Xe Cabin Phương Trang)
(1, 1, 2, 1, 3, 305, 420, 270000),  -- TP.HCM -> Đà Lạt (Xe Giường nằm Phương Trang)
(2, 1, 3, 2, 4, 411, 480, 520000),  -- Ga Sài Gòn -> Ga Nha Trang (Tàu SE2)
(3, 4, 5, 6, 8, 315, 330, 420000),  -- Hà Nội -> Sa Pa (Sao Việt Limousine)
(2, 4, 6, 7, 9, 791, 960, 890000);  -- Ga Hà Nội -> Ga Đà Nẵng (Tàu SE)

-- 11. TRIPS (Lịch trình chạy trong hôm nay & ngày mai)
INSERT INTO trips (route_id, vehicle_id, driver_id, departure_time, arrival_time, ticket_price, trip_status) VALUES
(1, 1, 1, DATE_ADD(CURDATE(), INTERVAL 22 HOUR), DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL '4:30' HOUR_MINUTE), 340000, 'SCHEDULED'),
(2, 2, 1, DATE_ADD(CURDATE(), INTERVAL 23 HOUR), DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 6 HOUR), 270000, 'SCHEDULED'),
(3, 3, 2, DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 8 HOUR), DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 16 HOUR), 520000, 'SCHEDULED'),
(4, 4, 3, DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 7 HOUR), DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL '12:30' HOUR_MINUTE), 420000, 'SCHEDULED'),
(5, 3, 2, DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 1 DAY), INTERVAL 19 HOUR), DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 2 DAY), INTERVAL 11 HOUR), 890000, 'SCHEDULED');

-- 12. KHỞI TẠO SƠ ĐỒ GHẾ THỜI GIAN THỰC CHO TẤT CẢ CHUYẾN (trip_seats)
INSERT INTO trip_seats (trip_id, v_seat_id, seat_code, coach_or_deck, seat_tier, final_price, seat_status)
SELECT
    t.trip_id,
    vs.v_seat_id,
    vs.seat_code,
    vs.coach_or_deck,
    vs.seat_tier,
    ROUND(t.ticket_price * vs.price_multiplier, 0),
    'AVAILABLE'
FROM trips t
JOIN vehicle_seats vs ON t.vehicle_id = vs.vehicle_id;

-- Đánh dấu sẵn vài ghế đã đặt để giao diện trực quan
UPDATE trip_seats SET seat_status = 'BOOKED' WHERE trip_id = 1 AND seat_code = 'A01';

-- 13. CHÍNH SÁCH HỦY VÉ
INSERT INTO cancellation_policies (policy_name, hours_before_departure, refund_percentage, description) VALUES
('Hủy sớm trên 24 giờ', 24, 90.00, 'Hoàn 90% giá vé gốc nếu hủy trước giờ khởi hành từ 24 giờ trở lên.'),
('Hủy từ 6 đến 24 giờ', 6, 50.00, 'Hoàn 50% giá vé gốc nếu hủy trước giờ khởi hành từ 6 đến dưới 24 giờ.'),
('Hủy sát giờ dưới 6 giờ', 0, 0.00, 'Không hỗ trợ hoàn tiền khi hủy dưới 6 giờ trước khởi hành.');

-- 14. MÃ GIẢM GIÁ
INSERT INTO promotions (operator_id, promo_code, discount_type, discount_value, min_order_amount, max_discount_amount, usage_limit, valid_from, valid_to) VALUES
(NULL, 'VEXETAU50', 'FIXED_AMOUNT', 50000, 250000, 50000, 500, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_ADD(NOW(), INTERVAL 30 DAY)),
(NULL, 'DBMS20', 'PERCENT', 20, 200000, 100000, 200, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_ADD(NOW(), INTERVAL 30 DAY)),
(1, 'FUTA30K', 'FIXED_AMOUNT', 30000, 200000, 30000, 100, DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_ADD(NOW(), INTERVAL 30 DAY));

-- 15. BANNERS & NEWS
INSERT INTO banners_news (item_type, title, summary, badge_text) VALUES
('BANNER', 'Ưu đãi tuyến TP.HCM - Đà Lạt & Tàu hỏa 5 sao SE', 'Nhập mã VEXETAU50 giảm ngay 50.000đ cho mọi giao dịch thanh toán QR.', 'HOT DEAL'),
('NEWS', 'Đường sắt Việt Nam nâng cấp toa giường nằm khoang 4 điều hòa tuyến Bắc - Nam', 'Hành khách có thể chọn trực tiếp vị trí tầng/toa theo thời gian thực.', 'TIN TỨC');

-- 16. TẠO 1 ĐƠN VÉ MẪU ĐỂ TEST TRA CỨU / SOÁT QR / HỦY VÉ NGAY LẬP TỨC
INSERT INTO bookings (booking_code, user_id, contact_name, contact_phone, contact_email, subtotal_amount, discount_amount, service_fee, total_amount, commission_amount, booking_status)
VALUES ('VXT-888999', 1, 'Nguyễn Minh Khoa', '0901234567', 'khoa.nguyen@gmail.com', 680000, 50000, 10000, 640000, 54400, 'CONFIRMED');

INSERT INTO tickets (ticket_code, booking_id, trip_id, trip_seat_id, passenger_name, passenger_phone, pickup_point, dropoff_point, ticket_price, qr_payload)
SELECT 'TK-888999-A01', 1, 1, trip_seat_id, 'Nguyễn Minh Khoa', '0901234567', 'Bến xe Miền Đông Mới', 'Bến xe Liên tỉnh Đà Lạt', 340000, 'VEXETAU|VXT-888999|TRIP:1|SEAT:A01'
FROM trip_seats WHERE trip_id = 1 AND seat_code = 'A01';

INSERT INTO payments (booking_id, transaction_ref, payment_method, transaction_type, amount, payment_status)
VALUES (1, 'VNPAY-2026-888999', 'VNPAY', 'PAYMENT', 640000, 'SUCCESS');
