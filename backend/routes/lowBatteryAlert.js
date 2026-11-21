'use strict';
// POST /safety/low-battery-alert
// Reference implementation (Express + pg + Twilio). Adapt `db` / `requireAuth` to your stack.
// Credentials live ONLY in the environment: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN,
// TWILIO_MESSAGING_SERVICE_SID (or TWILIO_FROM), DEFAULT_COUNTRY_CODE (e.g. +91).
const express = require('express');
const twilio = require('twilio');

const sms = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
const DEFAULT_CC = process.env.DEFAULT_COUNTRY_CODE || '+91';
const STALE_MS = 10 * 60 * 1000;

const pad = (n) => String(n).padStart(2, '0');
function fmt(ms, tz) {
  const d = new Date(ms + tz * 60000);
  const sign = tz >= 0 ? '+' : '-', a = Math.abs(tz);
  return `${d.getUTCDate()}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())} (UTC${sign}${pad(Math.floor(a / 60))}:${pad(a % 60)})`;
}
function age(ms) {
  const m = Math.floor(ms / 60000);
  return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : m < 2880 ? `${Math.floor(m / 60)} h ago` : `${Math.floor(m / 1440)} days ago`;
}
function toE164(raw) {
  const s = String(raw || '').replace(/[^\d+]/g, '');
  if (/^\+[1-9]\d{7,14}$/.test(s)) return s;
  if (/^\d{10}$/.test(s)) return DEFAULT_CC + s;
  return null;
}
const mask = (p) => p.slice(0, 3) + '*'.repeat(Math.max(0, p.length - 5)) + p.slice(-2);

function buildBody({ name, battery, threshold, capturedAt, tz, loc }) {
  const who = name ? `${name}'s phone` : 'Your trusted contact\'s phone';
  let where = 'Last location: not available (no location has been recorded).';
  if (loc) {
    const link = `https://www.openstreetmap.org/?mlat=${loc.lat.toFixed(6)}&mlon=${loc.lng.toFixed(6)}`;
    const stale = capturedAt - loc.recordedAt > STALE_MS;
    where = `Last available location:\n${link}\nLocation recorded: ${fmt(loc.recordedAt, tz)} (${age(capturedAt - loc.recordedAt)})` +
      (stale ? ' - OUT OF DATE, may not be their current position' : '');
  }
  return `ROUTESHIELD SAFETY ALERT\n\n${who} battery has reached a critical level (${threshold}% or below).\n\n${where}\n\n` +
    `Battery level: ${battery}%\nTime: ${fmt(capturedAt, tz)}\n\n` +
    'This is an automatic low-battery safety notification. Please try contacting them if necessary.';
}

module.exports = ({ db, requireAuth }) => {
  const router = express.Router();

  router.post('/safety/low-battery-alert', requireAuth, async (req, res) => {
    const b = req.body || {};
    const battery = Number(b.batteryLevel), threshold = Number(b.threshold);
    const tz = Math.max(-840, Math.min(840, Number(b.tzOffsetMinutes) || 0));
    const capturedAt = Date.parse(b.capturedAt);
    if (!/^ep-\d{10,16}$/.test(b.episodeId || '') || !(battery >= 0 && battery <= 100) ||
        !(threshold >= 1 && threshold <= 100) || Number.isNaN(capturedAt)) {
      return res.status(400).json({ errorCode: 'bad_request' });
    }
    let loc = null;
    if (b.location) {
      const lat = Number(b.location.lat), lng = Number(b.location.lng), rec = Date.parse(b.location.recordedAt);
      if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !Number.isNaN(rec)) {
        loc = { lat, lng, recordedAt: rec, acc: Number(b.location.accuracyM) || null };
      }
    }
    const userId = req.user.id;

    // Abuse guard: at most 5 distinct episodes per user per 24h.
    const recent = await db.query(
      "select count(*)::int n from emergency_alerts where user_id=$1 and created_at > now() - interval '24 hours' and episode_id<>$2",
      [userId, b.episodeId]);
    if (recent.rows[0].n >= 5) return res.status(429).json({ errorCode: 'rate_limited' });

    await db.query(
      `insert into emergency_alerts (user_id, episode_id, battery_level, latitude, longitude, location_recorded_at, location_accuracy_m, captured_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8) on conflict (user_id, episode_id) do nothing`,
      [userId, b.episodeId, battery, loc?.lat ?? null, loc?.lng ?? null, loc ? new Date(loc.recordedAt) : null, loc?.acc ?? null, new Date(capturedAt)]);
    const alert = (await db.query('select * from emergency_alerts where user_id=$1 and episode_id=$2', [userId, b.episodeId])).rows[0];

    const contacts = (await db.query('select id, name, phone from trusted_contacts where user_id=$1', [userId])).rows;
    if (!contacts.length) {
      await db.query("update emergency_alerts set status='no_contacts', updated_at=now() where id=$1", [alert.id]);
      return res.json({ accepted: 0, failed: 0, total: 0, errorCode: 'no_contacts' });
    }

    const done = new Set((await db.query(
      "select contact_id from emergency_alert_deliveries where alert_id=$1 and error_code is null", [alert.id])).rows.map((r) => r.contact_id));
    const name = (await db.query('select name from users where id=$1', [userId])).rows[0]?.name;
    const body = buildBody({ name, battery, threshold, capturedAt, tz, loc });

    let accepted = done.size, failed = 0;
    for (const c of contacts) {
      if (done.has(String(c.id))) continue; // never text the same contact twice for one episode
      const to = toE164(c.phone);
      try {
        if (!to) throw Object.assign(new Error('Invalid phone number'), { code: 'invalid_number' });
        const m = await sms.messages.create({
          to, body,
          ...(process.env.TWILIO_MESSAGING_SERVICE_SID
            ? { messagingServiceSid: process.env.TWILIO_MESSAGING_SERVICE_SID }
            : { from: process.env.TWILIO_FROM }),
        });
        await db.query(
          `insert into emergency_alert_deliveries (alert_id, contact_id, to_masked, provider, provider_sid, provider_status)
           values ($1,$2,$3,'twilio',$4,$5)
           on conflict (alert_id, contact_id) do update set provider_sid=excluded.provider_sid, provider_status=excluded.provider_status, error_code=null, error_message=null`,
          [alert.id, String(c.id), mask(to || ''), m.sid, m.status]);
        accepted++; // "accepted by provider" only. Real delivery needs a status callback webhook.
      } catch (e) {
        failed++;
        await db.query(
          `insert into emergency_alert_deliveries (alert_id, contact_id, to_masked, provider, error_code, error_message)
           values ($1,$2,$3,'twilio',$4,$5)
           on conflict (alert_id, contact_id) do update set error_code=excluded.error_code, error_message=excluded.error_message`,
          [alert.id, String(c.id), mask(to || ''), String(e.code || 'send_failed'), String(e.message).slice(0, 300)]);
      }
    }
    const status = accepted === 0 ? 'failed' : failed === 0 ? 'accepted' : 'partial';
    await db.query('update emergency_alerts set status=$2, updated_at=now() where id=$1', [alert.id, status]);
    res.json({ accepted, failed, total: contacts.length, duplicate: done.size === contacts.length });
  });

  return router;
};
