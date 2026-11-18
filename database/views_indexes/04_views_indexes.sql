-- ============================================================================
-- VEXETAU DBMS ARCHITECTURE - STEP 4: INDEXING & ANALYTICAL VIEWS
-- ============================================================================
USE vexetau_db;

-- 1. COMPOSITE INDEXES TỐI ƯU HIỆU NĂNG TRUY VẤN
CREATE INDEX idx_trips_search_route_date ON trips (route_id, departure_time, trip_status);
CREATE INDEX idx_trip_seats_status ON trip_seats (trip_id, seat_status, lock_expires_at);
CREATE INDEX idx_bookings_phone_code ON bookings (contact_phone, booking_code);
CREATE INDEX idx_audit_logs_created ON audit_logs (created_at DESC);
CREATE INDEX idx_trip_seats_expiry ON trip_seats (seat_status, lock_expires_at);

-- 2. VIEW CHI TIẾT CHUYẾN ĐI & TỶ LỆ LẤP ĐẦY GHẾ THỜI GIAN THỰC
CREATE OR REPLACE VIEW vw_trip_availability AS
SELECT
    t.trip_id,
    t.departure_time,
    t.arrival_time,
    t.ticket_price,
    t.trip_status,
    r.route_id,
    r.distance_km,
    r.estimated_duration_mins,
    orig_loc.location_id AS origin_id,
    orig_loc.name AS origin_city,
    orig_sta.station_name AS origin_station,
    orig_sta.latitude AS origin_lat,
    orig_sta.longitude AS origin_lng,
    dest_loc.location_id AS destination_id,
    dest_loc.name AS destination_city,
    dest_sta.station_name AS destination_station,
    dest_sta.latitude AS dest_lat,
    dest_sta.longitude AS dest_lng,
    o.operator_id,
    o.company_name,
    o.transport_category,
    o.rating_avg,
    o.total_reviews,
    v.vehicle_id,
    v.plate_or_train_code,
    v.vehicle_type,
    v.amenities,
    v.total_seats,
    SUM(CASE WHEN ts.seat_status = 'AVAILABLE' THEN 1 ELSE 0 END) AS available_seats,
    SUM(CASE WHEN ts.seat_status = 'LOCKED' THEN 1 ELSE 0 END) AS locked_seats,
    SUM(CASE WHEN ts.seat_status = 'BOOKED' THEN 1 ELSE 0 END) AS booked_seats,
    ROUND((SUM(CASE WHEN ts.seat_status = 'BOOKED' THEN 1 ELSE 0 END) / v.total_seats) * 100, 1) AS occupancy_rate
FROM trips t
JOIN routes r ON t.route_id = r.route_id
JOIN locations orig_loc ON r.origin_location_id = orig_loc.location_id
JOIN locations dest_loc ON r.destination_location_id = dest_loc.location_id
JOIN stations orig_sta ON r.origin_station_id = orig_sta.station_id
JOIN stations dest_sta ON r.destination_station_id = dest_sta.station_id
JOIN operators o ON r.operator_id = o.operator_id
JOIN vehicles v ON t.vehicle_id = v.vehicle_id
LEFT JOIN trip_seats ts ON t.trip_id = ts.trip_id
WHERE o.approval_status = 'APPROVED'
GROUP BY t.trip_id;

-- 3. VIEW THỐNG KÊ DOANH THU THEO NHÀ XE / ĐƠN VỊ VẬN HÀNH
CREATE OR REPLACE VIEW vw_operator_revenue_report AS
SELECT
    o.operator_id,
    o.company_name,
    o.transport_category,
    o.commission_rate,
    COUNT(DISTINCT b.booking_id) AS total_bookings,
    COUNT(CASE WHEN b.booking_id IS NOT NULL THEN tk.ticket_id END) AS total_tickets_sold,
    COALESCE(SUM(CASE WHEN b.booking_id IS NOT NULL THEN tk.ticket_price ELSE 0 END), 0) AS gross_revenue,
    COALESCE(SUM(CASE WHEN b.booking_id IS NOT NULL THEN tk.ticket_price * (o.commission_rate / 100) ELSE 0 END), 0) AS platform_commission,
    COALESCE(SUM(CASE WHEN b.booking_id IS NOT NULL THEN tk.ticket_price * (1 - o.commission_rate / 100) ELSE 0 END), 0) AS net_operator_revenue
FROM operators o
LEFT JOIN routes r ON o.operator_id = r.operator_id
LEFT JOIN trips t ON r.route_id = t.route_id
LEFT JOIN tickets tk ON t.trip_id = tk.trip_id AND tk.checkin_status <> 'CANCELLED'
LEFT JOIN bookings b ON tk.booking_id = b.booking_id AND b.booking_status = 'CONFIRMED'
GROUP BY o.operator_id;
