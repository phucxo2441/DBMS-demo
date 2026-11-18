const express = require('express');
const router = express.Router();
const customerCtrl = require('../controllers/customerController');
const operatorCtrl = require('../controllers/operatorController');
const adminCtrl = require('../controllers/adminController');

// --- 1. CUSTOMER ENDPOINTS ---
router.get('/bootstrap', customerCtrl.getBootstrapData);
router.get('/trips', customerCtrl.searchTrips);
router.get('/trips/:tripId/seats', customerCtrl.getTripSeats);
router.post('/seats/hold', customerCtrl.holdSeat);
router.post('/seats/release', customerCtrl.releaseSeat);
router.post('/bookings/confirm', customerCtrl.confirmBooking);
router.get('/bookings/lookup', customerCtrl.lookupBooking);
router.post('/bookings/cancel', customerCtrl.cancelBooking);
router.post('/reviews', customerCtrl.submitReview);

// --- 2. OPERATOR ENDPOINTS ---
router.get('/operator/dashboard', operatorCtrl.getOperatorDashboard);
router.post('/operator/trips', operatorCtrl.createTrip);
router.post('/operator/checkin', operatorCtrl.scanCheckInQR);

// --- 3. ADMIN & DBMS MONITOR ENDPOINTS ---
router.get('/admin/overview', adminCtrl.getAdminOverview);
router.post('/admin/operators/status', adminCtrl.updateOperatorStatus);

module.exports = router;
