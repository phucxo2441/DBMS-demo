# VEXETAU - Hệ Thống Đặt Vé & Quản Lý Vận Tải Đa Phương Tiện (DBMS Edition)

Dự án demo hệ thống đặt vé xe khách / tàu hỏa được thiết kế **chuyên sâu về Cơ sở dữ liệu (DBMS - MySQL 8.0 / MariaDB)** kết hợp kiến trúc Full-Stack (Node.js + Express + Vanilla JS SPA).

---

## 1. Điểm Nhấn Kiến Trúc DBMS (Database Management System)

Dự án tập trung xử lý toàn bộ nghiệp vụ cốt lõi và toàn vẹn dữ liệu ngay tại tầng Database:

1. **Schema & Ràng buộc toàn vẹn (`database/migrations/01_schema.sql`)**:
   - 22 bảng bao phủ khách hàng, đơn vị vận hành, quản trị viên, thanh toán và audit log.
   - Sử dụng `CHECK constraints`, `FOREIGN KEY (ON DELETE RESTRICT/CASCADE)`, `UNIQUE` composite keys (ví dụ: không cho phép trùng `seat_code` trong cùng 1 `vehicle_id`).
   - Mỗi ghế/chuyến chỉ có một vé; khóa ngoại ghép bảo đảm vé tham chiếu đúng ghế của đúng chuyến.
   - Trạng thái khóa ghế phải có phiên và thời hạn; cột `version` theo dõi các lần cập nhật trạng thái.

2. **Stored Procedures & ACID Transactions (`database/procedures/02_stored_procedures.sql`)**:
   - `sp_HoldSeatWithLock`: Dùng **`SELECT ... FOR UPDATE`** để khóa ghế theo hàng, giới hạn thời gian giữ chỗ và ghi audit trong cùng transaction.
   - `sp_ConfirmBookingAndPay`: Chỉ thanh toán ghế được chính phiên người dùng giữ; kiểm tra chuyến, phạm vi voucher, số dư điểm và cập nhật booking/vé/thanh toán trong transaction.
   - `sp_CancelBookingAndRefund`: Tính tỷ lệ hoàn theo thời gian trước giờ khởi hành và cập nhật trạng thái booking, vé, ghế trong transaction.
   - `sp_OperatorCheckInQR`: Khóa dòng vé trong lúc soát để ngăn hai lượt quét đồng thời cùng xác nhận một vé.

3. **Triggers & Scheduled Events (`database/triggers_events/03_triggers_events.sql`)**:
   - `trg_bookings_after_update_audit`: Tự động ghi **Audit Log** vào bảng `audit_logs` mỗi khi đơn đặt vé thay đổi trạng thái (kèm dữ liệu JSON trước và sau khi sửa).
   - `trg_reviews_after_insert`: Tự động tính lại điểm đánh giá trung bình (`rating_avg`) của Nhà xe ngay khi có nhận xét mới.
   - `evt_auto_release_expired_seats` (**MySQL Event Scheduler** chạy mỗi 10 giây): Tự động quét các ghế đang giữ chỗ tạm thời (`LOCKED`) đã quá hạn `lock_expires_at` để nhả ghế về `AVAILABLE` mà không cần phụ thuộc hoàn toàn vào backend.

4. **Views & Indexes (`database/views_indexes/04_views_indexes.sql`)**:
   - Indexes tối ưu tìm kiếm chuyến, tra cứu đơn và quét ghế hết hạn.
   - `vw_trip_availability` tổng hợp chỗ còn trống; `vw_operator_revenue_report` chỉ tính vé của đơn đã xác nhận.

---

## 2. Cấu Trúc Thư Mục Dự Án

```text
vexetau-dbms-project/
├── database/
│   ├── migrations/
│   │   └── 01_schema.sql              # DDL: 22 bảng, PK, FK, Constraints, RBAC
│   ├── procedures/
│   │   └── 02_stored_procedures.sql   # ACID Transactions, SELECT FOR UPDATE, Hoàn vé, Soát QR
│   ├── triggers_events/
│   │   └── 03_triggers_events.sql     # Audit Log Triggers, Auto-rating, Event Scheduler nhả ghế
│   ├── views_indexes/
│   │   └── 04_views_indexes.sql       # Composite Indexes, Views báo cáo doanh thu & lấp đầy
│   └── seeds/
│       └── 05_seed_data.sql           # Dữ liệu mẫu Việt Nam (Tuyến đường, Nhà xe, Tàu hỏa, Chuyến, User)
├── backend/
│   ├── config/
│   │   ├── db.js                      # Connection Pool (mysql2/promise)
│   │   └── procedures.js              # Gọi procedure và đọc OUT parameters cùng connection
│   ├── controllers/
│   │   ├── customerController.js      # Gọi Stored Procedures đặt vé, giữ ghế, hủy vé, tra cứu
│   │   ├── operatorController.js      # Quản lý chuyến, danh sách khách, soát vé QR, doanh thu
│   │   └── adminController.js         # RBAC, duyệt nhà xe, cấu hình chính sách, xem Audit Log & DB Monitor
│   ├── routes/
│   │   └── api.js                     # RESTful API Endpoints
│   └── server.js                      # Express Server + Background Worker đồng bộ & Phục vụ Frontend
├── frontend/
│   ├── assets/
│   │   ├── css/style.css              # Giao diện hiện đại (Tailwind + Custom CSS)
│   │   └── js/app.js                  # Logic SPA: Khách hàng, Nhà xe, Admin, SQL Inspector
│   └── index.html                     # Giao diện chính đa phân hệ (Việt/Anh)
├── .env.example                       # Cấu hình biến môi trường kết nối MySQL
├── package.json                       # Khai báo thư viện Node.js
├── .gitignore                         # Loại trừ .env và node_modules
└── README.md                          # Tài liệu hướng dẫn cài đặt & vận hành
```

---

## 3. Hướng Dẫn Cài Đặt & Chạy Trên Localhost

### Bước 1: Chuẩn bị môi trường
- **Node.js** (phiên bản 18.11 trở lên): [https://nodejs.org/](https://nodejs.org/)
- **MySQL 8.0.16+** (hoặc XAMPP / Laragon / Docker MySQL), để áp dụng đầy đủ các `CHECK constraints`.

### Bước 2: Khởi tạo Cơ sở dữ liệu (DBMS)
Mở **MySQL Workbench**, **DBeaver**, **phpMyAdmin** hoặc Terminal MySQL, chạy lần lượt 5 file SQL theo đúng thứ tự sau trên database mới:

```bash
mysql -u root -p < database/migrations/01_schema.sql
mysql -u root -p vexetau_db < database/procedures/02_stored_procedures.sql
mysql -u root -p vexetau_db < database/triggers_events/03_triggers_events.sql
mysql -u root -p vexetau_db < database/views_indexes/04_views_indexes.sql
mysql -u root -p vexetau_db < database/seeds/05_seed_data.sql
```
*(Lưu ý: Nếu dùng giao diện đồ họa như MySQL Workbench, bạn chỉ cần mở từng file theo thứ tự `01` -> `05` và bấm nút Execute ⚡).*

`01_schema.sql` không xóa database/dữ liệu hiện có. Đây là script khởi tạo ban đầu, không phải migration cập nhật schema; chỉ chạy trên database mới. Muốn tạo lại dữ liệu demo, hãy backup trước và xóa database thủ công một cách có chủ ý.

Event Scheduler là tùy chọn cấu hình của MySQL server. Nếu cần chạy event tự động, bật `event_scheduler` trong cấu hình MySQL hoặc bằng tài khoản quản trị (`SET GLOBAL event_scheduler = ON;`). Nếu không bật, backend vẫn có worker dự phòng để nhả ghế hết hạn.

### Bước 3: Cấu hình Backend
1. Mở Terminal tại thư mục gốc `vexetau-dbms-project`.
2. Tạo file `.env` từ file mẫu `.env.example` (PowerShell):
   ```bash
   Copy-Item .env.example .env
   ```
3. Mở file `.env` và điền mật khẩu MySQL của bạn (`DB_PASSWORD`).
4. Cài đặt các thư viện cần thiết:
   ```bash
   npm install
   ```

### Bước 4: Khởi chạy ứng dụng
```bash
npm start
```
Mở trình duyệt và truy cập: **`http://localhost:3000`**

---

## 4. Kịch Bản Test Tính Năng DBMS Khi Demo
1. **Test Concurrency Lock (`SELECT ... FOR UPDATE`)**:
   - Mở 2 tab trình duyệt ở `http://localhost:3000`.
   - Cùng chọn 1 chuyến xe và bấm giữ cùng 1 ghế `A01` gần như đồng thời.
   - Tab thứ nhất khóa ghế thành công (bắt đầu đếm ngược 120 giây); Tab thứ hai sẽ nhận thông báo lỗi từ Stored Procedure `sp_HoldSeatWithLock`: *"Ghế đã được giữ hoặc đặt bởi giao dịch khác!"*.
2. **Test Auto-Release Event Scheduler**:
   - Giữ 1 ghế nhưng không thanh toán, chờ hết thời gian đếm ngược (hoặc chỉnh `lock_expires_at` trong DB), MySQL Event `evt_auto_release_expired_seats` sẽ tự động trả ghế về trạng thái trống.
3. **Test Trigger Audit Log**:
   - Thay đổi trạng thái một booking rồi kiểm tra bản ghi được tạo trong `audit_logs` bởi trigger `trg_bookings_after_update_audit`.
