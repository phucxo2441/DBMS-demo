// Tạo Session ID duy nhất cho từng tab trình duyệt để test Concurrency Lock giữa 2 tab
const SESSION_ID = 'TAB-' + Math.random().toString(36).substring(2, 8).toUpperCase();
document.getElementById('session-id-label').textContent = SESSION_ID;

let currentTrip = null;
let selectedSeats = []; // [{ seat_code, final_price }]
let lockExpiryTimestamp = null;
let countdownInterval = null;
let seatPollInterval = null;

const formatMoney = (val) => Number(val || 0).toLocaleString('vi-VN') + 'đ';
const setLiveSQL = (sql) => { document.getElementById('live-sql-text').textContent = sql; };

// Khởi tạo ứng dụng
window.addEventListener('DOMContentLoaded', async () => {
    await checkDbHealth();
    await loadBootstrap();
    await loadTrips();

    // Set mặc định giờ khởi hành cho form tạo chuyến nhà xe
    const tomorrow = new Date(Date.now() + 86400000);
    document.getElementById('op-dep-time').value = tomorrow.toISOString().slice(0, 16);
});

async function checkDbHealth() {
    const badge = document.getElementById('db-status-badge');
    try {
        const res = await fetch('/api/health');
        const data = await res.json();
        if (data.success) {
            badge.className = 'text-xs font-mono-code px-3 py-1.5 rounded-lg bg-emerald-950 border border-emerald-700 text-emerald-300';
            badge.innerHTML = `<i class="fa-solid fa-circle-check mr-1"></i>MySQL ${data.dbms.mysql_version} (${data.dbms.active_db})`;
        } else {
            throw new Error(data.message);
        }
    } catch (err) {
        badge.className = 'text-xs font-mono-code px-3 py-1.5 rounded-lg bg-red-950 border border-red-700 text-red-300';
        badge.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1"></i>Lỗi kết nối MySQL`;
        alert('CẢNH BÁO KẾT NỐI DB: ' + err.message);
    }
}

function switchRoleTab(tab) {
    ['customer', 'operator', 'admin'].forEach(t => {
        document.getElementById(`view-${t}`).classList.add('hidden');
        const btn = document.getElementById(`tab-${t}`);
        btn.className = 'role-tab px-4 py-2 rounded-lg text-sm font-semibold text-slate-300 hover:text-white transition';
    });
    document.getElementById(`view-${tab}`).classList.remove('hidden');
    document.getElementById(`tab-${tab}`).className = 'role-tab px-4 py-2 rounded-lg text-sm font-semibold bg-blue-600 text-white transition';

    if (tab === 'operator') loadOperatorDashboard();
    if (tab === 'admin') loadAdminDashboard();
}

function switchCustomerSub(sub) {
    document.getElementById('customer-search-panel').classList.toggle('hidden', sub !== 'search');
    document.getElementById('customer-lookup-panel').classList.toggle('hidden', sub !== 'lookup');
}

async function loadBootstrap() {
    const res = await fetch('/api/bootstrap');
    const json = await res.json();
    if (!json.success) return;

    const { locations, currentUser } = json.data;
    if (currentUser) {
        document.getElementById('user-points').textContent = currentUser.loyalty_points;
    }

    const origSel = document.getElementById('filter-origin');
    const destSel = document.getElementById('filter-dest');
    locations.forEach(loc => {
        origSel.innerHTML += `<option value="${loc.location_id}">${loc.name}</option>`;
        destSel.innerHTML += `<option value="${loc.location_id}">${loc.name}</option>`;
    });
}

async function loadTrips() {
    const origin_id = document.getElementById('filter-origin').value;
    const destination_id = document.getElementById('filter-dest').value;
    const category = document.getElementById('filter-category').value;
    const sort_by = document.getElementById('filter-sort').value;

    const params = new URLSearchParams({ origin_id, destination_id, category, sort_by });
    const res = await fetch(`/api/trips?${params.toString()}`);
    const json = await res.json();

    if (json.sql_executed) setLiveSQL(json.sql_executed);

    const list = document.getElementById('trips-list');
    if (!json.data || json.data.length === 0) {
        list.innerHTML = `<div class="bg-white p-8 rounded-2xl text-center text-slate-500 border border-slate-200">Không tìm thấy chuyến đi phù hợp.</div>`;
        return;
    }

    list.innerHTML = json.data.map(trip => {
        const dep = new Date(trip.departure_time).toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' });
        const arr = new Date(trip.arrival_time).toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' });
        const isTrain = trip.transport_category === 'TRAIN';
        const amenities = typeof trip.amenities === 'string' ? JSON.parse(trip.amenities) : trip.amenities;

        return `
        <div class="bg-white p-5 rounded-2xl shadow-sm border border-slate-200 hover:border-blue-400 transition flex flex-col md:flex-row justify-between gap-4">
            <div class="space-y-2 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                    <span class="px-2.5 py-1 rounded-lg text-xs font-bold ${isTrain ? 'bg-indigo-100 text-indigo-700' : 'bg-blue-100 text-blue-700'}">
                        <i class="fa-solid ${isTrain ? 'fa-train' : 'fa-bus'} mr-1"></i>${isTrain ? 'TÀU HỎA' : 'XE KHÁCH'}
                    </span>
                    <h4 class="font-extrabold text-slate-900 text-base">${trip.company_name}</h4>
                    <span class="text-xs text-amber-600 font-bold"><i class="fa-solid fa-star"></i> ${trip.rating_avg} (${trip.total_reviews})</span>
                    <span class="text-xs font-mono-code text-slate-400">#${trip.plate_or_train_code}</span>
                </div>

                <div class="flex items-center gap-4 text-sm">
                    <div>
                        <div class="font-bold text-slate-900">${dep}</div>
                        <div class="text-xs text-slate-500">${trip.origin_city} (${trip.origin_station})</div>
                    </div>
                    <div class="flex-1 max-w-[140px] text-center">
                        <div class="text-[11px] text-slate-400">${Math.floor(trip.estimated_duration_mins/60)}h${trip.estimated_duration_mins%60}p • ${trip.distance_km}km</div>
                        <div class="h-0.5 bg-slate-300 my-1 relative"><i class="fa-solid fa-circle-arrow-right text-blue-600 absolute -top-1.5 right-0 text-xs"></i></div>
                    </div>
                    <div>
                        <div class="font-bold text-slate-900">${arr}</div>
                        <div class="text-xs text-slate-500">${trip.destination_city} (${trip.destination_station})</div>
                    </div>
                </div>

                <div class="flex flex-wrap gap-1.5 pt-1">
                    ${amenities.map(a => `<span class="text-[11px] bg-slate-100 text-slate-600 px-2 py-0.5 rounded-md">${a}</span>`).join('')}
                </div>
            </div>

            <div class="md:text-right flex flex-row md:flex-col justify-between items-end border-t md:border-t-0 pt-3 md:pt-0 border-slate-100">
                <div>
                    <div class="text-xs text-slate-500">Giá từ</div>
                    <div class="text-xl font-extrabold text-blue-700">${formatMoney(trip.ticket_price)}</div>
                    <div class="text-xs font-semibold ${trip.available_seats > 5 ? 'text-emerald-600' : 'text-amber-600'}">
                        Còn ${trip.available_seats}/${trip.total_seats} chỗ trống
                    </div>
                </div>
                <button onclick='openSeatModal(${JSON.stringify(trip)})' class="bg-blue-600 hover:bg-blue-700 text-white font-bold px-5 py-2.5 rounded-xl text-sm shadow">
                    Chọn Chỗ & Đặt Vé
                </button>
            </div>
        </div>`;
    }).join('');
}

// ============================================================================
// SƠ ĐỒ GHẾ THỜI GIAN THỰC & PESSIMISTIC LOCKING (SELECT ... FOR UPDATE)
// ============================================================================
async function openSeatModal(trip) {
    currentTrip = trip;
    selectedSeats = [];
    document.getElementById('modal-trip-title').textContent = `${trip.company_name} — ${trip.origin_city} → ${trip.destination_city}`;
    document.getElementById('modal-trip-subtitle').textContent = `Phương tiện: ${trip.plate_or_train_code} | Khởi hành: ${new Date(trip.departure_time).toLocaleString('vi-VN')}`;
    document.getElementById('bk-pickup').value = trip.origin_station;
    document.getElementById('bk-dropoff').value = trip.destination_station;
    updateSelectedSeatsUI();

    document.getElementById('booking-modal').classList.remove('hidden');
    await refreshSeatMap();

    // Polling mỗi 3 giây để thấy ghế người khác vừa khóa theo thời gian thực
    clearInterval(seatPollInterval);
    seatPollInterval = setInterval(refreshSeatMap, 3000);
}

function closeBookingModal() {
    document.getElementById('booking-modal').classList.add('hidden');
    clearInterval(seatPollInterval);
    clearInterval(countdownInterval);
}

async function refreshSeatMap() {
    if (!currentTrip) return;
    const res = await fetch(`/api/trips/${currentTrip.trip_id}/seats`);
    const json = await res.json();
    if (!json.success) return;

    // Nhóm ghế theo Tầng hoặc Toa tàu
    const groups = {};
    json.data.forEach(s => {
        if (!groups[s.coach_or_deck]) groups[s.coach_or_deck] = [];
        groups[s.coach_or_deck].push(s);
    });

    const container = document.getElementById('seat-map-container');
    container.innerHTML = Object.entries(groups).map(([deckName, seats]) => `
        <div class="bg-slate-50 p-4 rounded-2xl border border-slate-200">
            <div class="text-xs font-extrabold text-slate-600 uppercase mb-3 flex justify-between">
                <span><i class="fa-solid fa-layer-group mr-1 text-blue-600"></i>${deckName}</span>
                <span>${seats.filter(x => x.seat_status === 'AVAILABLE').length} trống</span>
            </div>
            <div class="grid grid-cols-4 gap-2.5">
                ${seats.map(s => {
                    let cls = 'seat-available';
                    let disabled = '';
                    let sub = formatMoney(s.final_price);

                    if (s.seat_status === 'BOOKED') {
                        cls = 'seat-booked';
                        disabled = 'disabled';
                        sub = 'Đã bán';
                    } else if (s.seat_status === 'LOCKED') {
                        if (s.locked_by_session === SESSION_ID) {
                            cls = 'seat-locked-me';
                            sub = 'Đang giữ';
                        } else {
                            cls = 'seat-locked-other';
                            disabled = 'disabled';
                            sub = 'Khách giữ';
                        }
                    }

                    return `
                    <button ${disabled} onclick="toggleSeatLock('${s.seat_code}', ${s.final_price}, '${s.seat_status}')"
                        class="seat-btn ${cls} p-2 rounded-xl text-center">
                        <div class="font-mono-code font-bold text-xs">${s.seat_code}</div>
                        <div class="text-[10px] opacity-85 mt-0.5">${sub}</div>
                    </button>`;
                }).join('')}
            </div>
        </div>
    `).join('');
}

async function toggleSeatLock(seatCode, price, currentStatus) {
    const isAlreadyMine = selectedSeats.some(s => s.seat_code === seatCode);

    if (isAlreadyMine || currentStatus === 'LOCKED') {
        // Nhả ghế
        await fetch('/api/seats/release', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ trip_id: currentTrip.trip_id, seat_code: seatCode, session_id: SESSION_ID })
        });
        selectedSeats = selectedSeats.filter(s => s.seat_code !== seatCode);
        setLiveSQL(`CALL sp_ReleaseSeat(${currentTrip.trip_id}, '${seatCode}', '${SESSION_ID}');`);
    } else {
        // Khóa ghế qua Stored Procedure SELECT ... FOR UPDATE
        const res = await fetch('/api/seats/hold', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ trip_id: currentTrip.trip_id, seat_code: seatCode, session_id: SESSION_ID, hold_seconds: 120 })
        });
        const json = await res.json();
        if (json.db_procedure) setLiveSQL(json.db_procedure);

        if (!json.success) {
            alert('⚠️ XUNG ĐỘT ĐỒNG THỜI (DBMS LOCK): ' + json.message);
            await refreshSeatMap();
            return;
        }

        selectedSeats.push({ seat_code: seatCode, final_price: price });
        startLockCountdown(120);
    }

    updateSelectedSeatsUI();
    await refreshSeatMap();
}

function startLockCountdown(seconds) {
    clearInterval(countdownInterval);
    let remaining = seconds;
    const box = document.getElementById('lock-countdown-box');
    const timerEl = document.getElementById('lock-timer');
    box.classList.remove('hidden');

    countdownInterval = setInterval(async () => {
        remaining--;
        const mins = String(Math.floor(remaining / 60)).padStart(2, '0');
        const secs = String(remaining % 60).padStart(2, '0');
        timerEl.textContent = `${mins}:${secs}`;

        if (remaining <= 0) {
            clearInterval(countdownInterval);
            box.classList.add('hidden');
            selectedSeats = [];
            updateSelectedSeatsUI();
            alert('⏰ Hết thời gian giữ chỗ 120 giây! Hệ thống DBMS đã tự động nhả ghế.');
            await refreshSeatMap();
        }
    }, 1000);
}

function updateSelectedSeatsUI() {
    const label = document.getElementById('selected-seats-display');
    const subEl = document.getElementById('bk-subtotal-text');
    if (selectedSeats.length === 0) {
        label.textContent = 'Chưa chọn ghế';
        subEl.textContent = '0đ';
        document.getElementById('lock-countdown-box').classList.add('hidden');
    } else {
        label.textContent = selectedSeats.map(s => s.seat_code).join(', ');
        const sum = selectedSeats.reduce((acc, s) => acc + Number(s.final_price), 0);
        subEl.textContent = formatMoney(sum);
    }
}

async function submitBookingPayment() {
    if (selectedSeats.length === 0) {
        alert('Vui lòng chọn ít nhất 1 ghế/giường trước khi thanh toán!');
        return;
    }

    const payload = {
        user_id: 1,
        session_id: SESSION_ID,
        trip_id: currentTrip.trip_id,
        seat_codes: selectedSeats.map(s => s.seat_code),
        contact_name: document.getElementById('bk-name').value,
        contact_phone: document.getElementById('bk-phone').value,
        contact_email: document.getElementById('bk-email').value,
        pickup_point: document.getElementById('bk-pickup').value,
        dropoff_point: document.getElementById('bk-dropoff').value,
        promo_code: document.getElementById('bk-promo').value.trim().toUpperCase(),
        use_points: document.getElementById('bk-use-points').checked ? 20 : 0,
        payment_method: document.getElementById('bk-payment').value,
        vat_requested: document.getElementById('bk-vat').checked,
        vat_tax_code: document.getElementById('bk-vat-tax').value,
        vat_company: document.getElementById('bk-vat-company').value
    };

    const res = await fetch('/api/bookings/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });
    const json = await res.json();
    if (json.db_procedure) setLiveSQL(json.db_procedure);

    if (json.success) {
        alert(`🎉 ${json.message}
Mã đặt chỗ của bạn: ${json.booking_code}`);
        closeBookingModal();
        await loadBootstrap();
        await loadTrips();

        // Tự động điền mã vé vừa đặt vào tab Tra cứu
        document.getElementById('lookup-code').value = json.booking_code;
        document.getElementById('lookup-phone').value = payload.contact_phone;
        switchCustomerSub('lookup');
        lookupTicket();
    } else {
        alert('❌ Lỗi đặt vé: ' + json.message);
    }
}

// ============================================================================
// TRA CỨU VÉ, HỦY VÉ HOÀN TIỀN & ĐÁNH GIÁ
// ============================================================================
async function lookupTicket() {
    const code = document.getElementById('lookup-code').value.trim();
    const phone = document.getElementById('lookup-phone').value.trim();
    const res = await fetch(`/api/bookings/lookup?booking_code=${encodeURIComponent(code)}&phone=${encodeURIComponent(phone)}`);
    const json = await res.json();

    const box = document.getElementById('lookup-result');
    if (!json.success) {
        box.innerHTML = `<div class="p-4 rounded-xl bg-red-50 text-red-700 text-sm font-semibold">${json.message}</div>`;
        return;
    }

    const { booking, tickets } = json.data;
    box.innerHTML = `
    <div class="border border-slate-200 rounded-2xl p-5 bg-slate-50 space-y-4">
        <div class="flex flex-wrap justify-between items-center gap-3 border-b border-slate-200 pb-3">
            <div>
                <span class="text-xs text-slate-500">Mã đặt vé:</span>
                <strong class="text-lg font-mono-code text-blue-700 ml-1">${booking.booking_code}</strong>
                <span class="ml-2 px-2.5 py-0.5 rounded-full text-xs font-bold ${booking.booking_status === 'CONFIRMED' ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-700'}">
                    ${booking.booking_status}
                </span>
            </div>
            <div class="text-right">
                <div class="text-xs text-slate-500">Tổng thanh toán (Đã giảm ${formatMoney(booking.discount_amount)})</div>
                <div class="text-lg font-extrabold text-slate-900">${formatMoney(booking.total_amount)}</div>
            </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            ${tickets.map(tk => `
            <div class="bg-white p-4 rounded-xl border border-slate-200 flex justify-between items-center">
                <div class="space-y-1 text-xs">
                    <div class="font-bold text-sm text-slate-900">${tk.company_name}</div>
                    <div>${tk.origin_city} → ${tk.destination_city}</div>
                    <div>Ghế/Giường: <strong class="text-blue-700 font-mono-code">${tk.seat_code}</strong> (${tk.coach_or_deck})</div>
                    <div>Mã QR vé: <code class="bg-slate-100 px-1.5 py-0.5 rounded font-bold">${tk.ticket_code}</code></div>
                    <div>Trạng thái soát vé: <strong>${tk.checkin_status}</strong></div>
                </div>
                <div class="w-16 h-16 bg-slate-900 text-white rounded-xl flex flex-col items-center justify-center text-[10px] font-mono-code p-1 text-center">
                    <i class="fa-solid fa-qrcode text-2xl mb-1"></i>
                    <span>${tk.seat_code}</span>
                </div>
            </div>`).join('')}
        </div>

        <div class="flex flex-wrap justify-between items-center gap-3 pt-2">
            ${booking.booking_status === 'CONFIRMED' ? `
            <button onclick="cancelTicket('${booking.booking_code}', '${booking.contact_phone}')" class="bg-red-600 hover:bg-red-700 text-white font-bold px-4 py-2 rounded-xl text-xs">
                <i class="fa-solid fa-ban mr-1"></i>Hủy Vé & Hoàn Tiền Theo Chính Sách
            </button>` : '<div></div>'}

            <div class="flex items-center gap-2">
                <select id="review-rating" class="border border-slate-300 rounded-lg px-2 py-1.5 text-xs bg-white">
                    <option value="5">5 ⭐ Tuyệt vời</option>
                    <option value="4">4 ⭐ Tốt</option>
                    <option value="3">3 ⭐ Bình thường</option>
                </select>
                <input id="review-comment" type="text" placeholder="Nhận xét chất lượng xe/tàu..." class="border border-slate-300 rounded-lg px-3 py-1.5 text-xs bg-white" />
                <button onclick="sendReview('${booking.booking_code}')" class="bg-amber-500 hover:bg-amber-600 text-white font-bold px-3 py-1.5 rounded-lg text-xs">
                    Gửi Đánh Giá
                </button>
            </div>
        </div>
    </div>`;
}

async function cancelTicket(booking_code, phone) {
    if (!confirm('Xác nhận hủy đơn vé này? Hệ thống sẽ gọi Stored Procedure sp_CancelBookingAndRefund để tính tỷ lệ hoàn tiền và nhả ghế.')) return;
    const res = await fetch('/api/bookings/cancel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ booking_code, phone })
    });
    const json = await res.json();
    setLiveSQL(`CALL sp_CancelBookingAndRefund('${booking_code}', '${phone}');`);
    alert(json.message);
    lookupTicket();
    loadTrips();
}

async function sendReview(booking_code) {
    const rating = Number(document.getElementById('review-rating').value);
    const comment = document.getElementById('review-comment').value;
    const res = await fetch('/api/reviews', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ booking_code, rating, comment })
    });
    const json = await res.json();
    alert(json.message);
}

// ============================================================================
// PHÂN HỆ 2: NHÀ XE / ĐƠN VỊ VẬN HÀNH
// ============================================================================
async function loadOperatorDashboard() {
    const res = await fetch('/api/operator/dashboard');
    const json = await res.json();
    if (!json.success) return;

    document.getElementById('op-revenue-tbody').innerHTML = json.data.revenue.map(r => `
        <tr>
            <td class="p-3 font-bold">${r.company_name}</td>
            <td class="p-3"><span class="px-2 py-0.5 rounded bg-slate-100 text-xs font-semibold">${r.transport_category}</span></td>
            <td class="p-3 font-mono-code">${r.total_tickets_sold}</td>
            <td class="p-3 font-bold">${formatMoney(r.gross_revenue)}</td>
            <td class="p-3 text-amber-700">${formatMoney(r.platform_commission)} (${r.commission_rate}%)</td>
            <td class="p-3 font-extrabold text-emerald-700">${formatMoney(r.net_operator_revenue)}</td>
        </tr>
    `).join('');

    document.getElementById('op-passengers-tbody').innerHTML = json.data.passengers.map(p => `
        <tr>
            <td class="p-3 font-mono-code font-bold text-blue-700">${p.ticket_code}</td>
            <td class="p-3">${p.passenger_name} <span class="text-xs text-slate-400">(${p.passenger_phone})</span></td>
            <td class="p-3 text-xs">${p.company_name}<br/><span class="text-slate-500">${p.origin_city} → ${p.destination_city}</span></td>
            <td class="p-3 font-mono-code font-bold">${p.seat_code}</td>
            <td class="p-3">
                <span class="px-2 py-0.5 rounded-full text-xs font-bold ${p.checkin_status === 'BOARDED' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}">
                    ${p.checkin_status}
                </span>
            </td>
        </tr>
    `).join('');
}

async function scanTicketQR() {
    const ticket_code = document.getElementById('qr-ticket-input').value;
    const res = await fetch('/api/operator/checkin', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ticket_code })
    });
    const json = await res.json();
    setLiveSQL(`CALL sp_OperatorCheckInQR('${ticket_code}');`);
    const box = document.getElementById('qr-scan-result');
    box.innerHTML = `<div class="p-3 rounded-xl font-bold ${json.success ? 'bg-emerald-100 text-emerald-800' : 'bg-red-100 text-red-800'}">${json.message}</div>`;
    loadOperatorDashboard();
}

async function createNewTrip() {
    const route_id = document.getElementById('op-route-id').value;
    const vehicle_id = document.getElementById('op-vehicle-id').value;
    const departure_time = document.getElementById('op-dep-time').value;
    const ticket_price = document.getElementById('op-price').value;

    const depDate = new Date(departure_time);
    const arrDate = new Date(depDate.getTime() + 6 * 3600000);

    const res = await fetch('/api/operator/trips', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            route_id,
            vehicle_id,
            departure_time: depDate.toISOString().slice(0, 19).replace('T', ' '),
            arrival_time: arrDate.toISOString().slice(0, 19).replace('T', ' '),
            ticket_price
        })
    });
    const json = await res.json();
    alert(json.message);
    loadOperatorDashboard();
}

// ============================================================================
// PHÂN HỆ 3: ADMIN & DBMS MONITOR
// ============================================================================
async function loadAdminDashboard() {
    const res = await fetch('/api/admin/overview');
    const json = await res.json();
    if (!json.success) return;

    const { kpi, operators } = json.data;

    document.getElementById('admin-kpi-grid').innerHTML = `
        <div class="bg-white p-4 rounded-2xl border border-slate-200"><div class="text-xs text-slate-500">Tổng GMV Giao Dịch</div><div class="text-xl font-extrabold text-blue-700 mt-1">${formatMoney(kpi.total_gmv)}</div></div>
        <div class="bg-white p-4 rounded-2xl border border-slate-200"><div class="text-xs text-slate-500">Doanh Thu Hoa Hồng</div><div class="text-xl font-extrabold text-emerald-600 mt-1">${formatMoney(kpi.total_commission)}</div></div>
        <div class="bg-white p-4 rounded-2xl border border-slate-200"><div class="text-xs text-slate-500">Đơn Vé Thành Công</div><div class="text-xl font-extrabold text-slate-900 mt-1">${kpi.confirmed_bookings}</div></div>
        <div class="bg-white p-4 rounded-2xl border border-slate-200"><div class="text-xs text-slate-500">Nhà Xe Hoạt Động</div><div class="text-xl font-extrabold text-slate-900 mt-1">${kpi.active_operators}</div></div>
        <div class="bg-white p-4 rounded-2xl border border-slate-200"><div class="text-xs text-slate-500">Ghế Đang Khóa Lock</div><div class="text-xl font-extrabold text-amber-600 mt-1">${kpi.active_seat_locks}</div></div>
    `;

    document.getElementById('admin-operators-tbody').innerHTML = operators.map(op => `
        <tr>
            <td class="p-3 font-bold">${op.company_name}</td>
            <td class="p-3 font-mono-code text-xs">${op.tax_code}</td>
            <td class="p-3 font-bold">${op.commission_rate}%</td>
            <td class="p-3">
                <span class="px-2.5 py-0.5 rounded-full text-xs font-bold ${op.approval_status === 'APPROVED' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}">
                    ${op.approval_status}
                </span>
            </td>
            <td class="p-3 space-x-1">
                <button onclick="setOperatorStatus(${op.operator_id}, 'APPROVED')" class="px-2.5 py-1 bg-emerald-600 text-white rounded-lg text-xs font-semibold">Duyệt</button>
                <button onclick="setOperatorStatus(${op.operator_id}, 'SUSPENDED')" class="px-2.5 py-1 bg-red-600 text-white rounded-lg text-xs font-semibold">Khóa</button>
            </td>
        </tr>
    `).join('');

}

async function setOperatorStatus(operator_id, approval_status) {
    await fetch('/api/admin/operators/status', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ operator_id, approval_status })
    });
    loadAdminDashboard();
}

