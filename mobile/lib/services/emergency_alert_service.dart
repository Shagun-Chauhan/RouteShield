import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/survival_config.dart';
import 'alert_gateway.dart';
import 'emergency_alert.dart';
import 'location_service.dart';

/// Last-known-location policy: try a fresh fix (foreground only), otherwise
/// use the last successfully recorded one. Never invents a location.
Future<LocationFix?> resolveLocation(SharedPreferences p, {required bool live}) async {
  if (live) {
    try {
      final cur = await LocationService.current().timeout(const Duration(seconds: 12));
      if (cur != null) await LocationService.save(p, cur);
    } catch (_) {}
  }
  final last = LocationService.load(p);
  if (last == null) return null;
  return LocationFix(lat: last.point.lat, lng: last.point.lng, at: last.at);
}

class EmergencyAlertService {
  EmergencyAlertService({required this.prefs, required this.gateway, this.contactCount});
  final SharedPreferences prefs;
  final AlertGateway gateway;

  /// Foreground-only local check (the worker relies on the server's answer).
  final Future<int> Function()? contactCount;

  static const _kHistory = 'alert_history';
  static const maxAttempts = 5;
  static const _backoffMin = [1, 2, 5, 10, 15];

  List<EmergencyAlertRecord> history() {
    final raw = prefs.getString(_kHistory);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => EmergencyAlertRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  EmergencyAlertRecord? get latest {
    final h = history();
    return h.isEmpty ? null : h.first;
  }

  EmergencyAlertRecord? byId(String id) {
    for (final r in history()) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<EmergencyAlertRecord> _save(EmergencyAlertRecord rec) async {
    final list = history();
    final i = list.indexWhere((r) => r.id == rec.id);
    i >= 0 ? list[i] = rec : list.insert(0, rec);
    await prefs.setString(_kHistory, jsonEncode(list.take(20).map((r) => r.toJson()).toList()));
    return rec;
  }

  /// Persists a queued record FIRST so a crash mid-send can be resumed.
  Future<EmergencyAlertRecord> dispatch({required int level, required String episodeId, required bool live}) async {
    var rec = await _save(EmergencyAlertRecord(
      id: episodeId,
      createdAt: DateTime.now(),
      battery: level,
      status: AlertStatus.queued,
      detail: 'Preparing alert',
    ));
    rec = await _save(rec.copyWith(fix: await resolveLocation(prefs, live: live)));
    return _attempt(rec);
  }

  /// Auto-retry of queued alerts whose backoff has elapsed. Returns the changed record, if any.
  Future<EmergencyAlertRecord?> retryDue({required bool live}) async {
    final cur = latest;
    if (cur == null || cur.status != AlertStatus.queued) return null;
    if (cur.nextRetryAt != null && DateTime.now().isBefore(cur.nextRetryAt!)) return null;
    final fix = cur.fix ?? await resolveLocation(prefs, live: live);
    return _attempt(cur.copyWith(fix: fix));
  }

  /// User-initiated retry (refreshes battery + location).
  Future<EmergencyAlertRecord?> retryNow(int level, {required bool live}) async {
    final cur = latest;
    if (cur == null || !const [AlertStatus.queued, AlertStatus.failed, AlertStatus.noContacts].contains(cur.status)) {
      return null;
    }
    final fix = await resolveLocation(prefs, live: live);
    return _attempt(cur.copyWith(battery: level, fix: fix, attempts: 0, clearRetry: true));
  }

  Future<void> markManualOpened(String id) async {
    final r = byId(id);
    if (r == null) return;
    await _save(r.copyWith(
      status: AlertStatus.manualOpened,
      detail: 'Opened in your messaging app. RouteShield cannot confirm that you sent it.',
      clearRetry: true,
    ));
  }

  Future<EmergencyAlertRecord> _attempt(EmergencyAlertRecord rec) async {
    if (prefs.getString('token') == 'demo') {
      return _save(rec.copyWith(
          status: AlertStatus.skipped, detail: 'Demo mode: no real message was sent.', clearRetry: true));
    }
    if (contactCount != null) {
      try {
        if (await contactCount!() == 0) {
          return _save(rec.copyWith(
              status: AlertStatus.noContacts, detail: 'No trusted contacts are saved.', clearRetry: true));
        }
      } catch (_) {/* offline: let the server decide */}
    }
    final attempts = rec.attempts + 1;
    try {
      final r = await gateway.submit(rec,
          threshold: SurvivalConfig.load(prefs).activateAt, tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes);
      if (r.errorCode == 'no_contacts') {
        return _save(rec.copyWith(
            status: AlertStatus.noContacts, detail: 'No trusted contacts are saved.', attempts: attempts, clearRetry: true));
      }
      if (r.accepted > 0) {
        return _save(rec.copyWith(
          status: r.failed == 0 ? AlertStatus.accepted : AlertStatus.partial,
          accepted: r.accepted,
          total: r.total,
          attempts: attempts,
          clearRetry: true,
          detail: 'Accepted by the SMS provider for ${r.accepted} of ${r.total} contacts. '
              'This is not proof the message reached a phone.',
        ));
      }
      return _retryOrFail(rec, attempts, 'The SMS provider did not accept the message.');
    } catch (_) {
      return _retryOrFail(rec, attempts, 'Could not reach the RouteShield server.');
    }
  }

  Future<EmergencyAlertRecord> _retryOrFail(EmergencyAlertRecord rec, int attempts, String why) {
    if (attempts >= maxAttempts) {
      return _save(rec.copyWith(
          status: AlertStatus.failed, attempts: attempts, clearRetry: true, detail: '$why Gave up after $attempts attempts.'));
    }
    final next = DateTime.now().add(Duration(minutes: _backoffMin[attempts - 1]));
    return _save(rec.copyWith(
        status: AlertStatus.queued, attempts: attempts, nextRetryAt: next, detail: '$why Will retry automatically.'));
  }
}
