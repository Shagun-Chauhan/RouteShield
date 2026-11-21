import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/survival_config.dart';
import 'battery_monitor.dart';
import 'emergency_alert.dart';
import 'emergency_alert_service.dart';
import 'survival_notifier.dart';
import 'survival_policy.dart';

/// Single place where a battery reading becomes: mode change, notification,
/// contact alert. Used by both the in-app monitor and the background worker
/// (no Riverpod/BuildContext), so behaviour is identical in both.
class SurvivalEngine {
  SurvivalEngine({required this.prefs, required this.alerts, required this.notifier});
  final SharedPreferences prefs;
  final EmergencyAlertService alerts;
  final SurvivalNotifier notifier;

  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await f());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  String _newEpisodeId() => 'ep-${DateTime.now().toUtc().millisecondsSinceEpoch}';

  Future<void> onBattery(BatterySnapshot s, {required bool live}) => _serial(() async {
        final cfg = SurvivalConfig.load(prefs);
        final out = SurvivalPolicy(cfg).evaluate(
          SurvivalStore.load(prefs),
          level: s.level,
          plugged: s.isPlugged,
          newEpisodeId: _newEpisodeId,
        );
        await SurvivalStore.save(prefs, out.state);

        if (out.activatedNow) {
          await notifier.show(1001, 'Survival Mode on',
              'Battery is at ${s.level}%. Location updates and background sync are reduced. SOS and emergency alerts stay active.');
        }
        if (out.deactivatedNow) {
          await notifier.show(1002, 'Survival Mode off', 'Battery recovered to ${s.level}%. Normal operation resumed.');
        }

        final ep = out.state.episodeId;
        EmergencyAlertRecord? changed;
        if (ep != null && cfg.notifyContacts && alerts.byId(ep) == null) {
          // Also covers an interrupted earlier attempt (episode saved, record missing).
          changed = await alerts.dispatch(level: s.level, episodeId: ep, live: live);
        } else {
          changed = await alerts.retryDue(live: live);
        }
        if (changed != null) await notifyOutcome(changed);
      });

  Future<SurvivalSnapshot> setManual(bool enabled, int? level) => _serial(() async {
        final cfg = SurvivalConfig.load(prefs);
        final next = SurvivalPolicy(cfg).setManual(SurvivalStore.load(prefs), enabled, level);
        await SurvivalStore.save(prefs, next);
        return next;
      });

  Future<void> notifyOutcome(EmergencyAlertRecord r) async {
    switch (r.status) {
      case AlertStatus.accepted:
      case AlertStatus.partial:
        await notifier.show(1003, 'Trusted contacts alerted',
            'Message accepted by the SMS provider for ${r.accepted} of ${r.total} contacts.');
      case AlertStatus.queued:
        await notifier.show(1003, 'Alert will be retried', 'Could not send yet. RouteShield will retry automatically.');
      case AlertStatus.failed:
        await notifier.show(1003, 'Could not alert contacts', 'Open RouteShield to retry or send the message yourself.');
      case AlertStatus.noContacts:
        await notifier.show(1003, 'No trusted contacts', 'Battery is critical but no contacts are saved to alert.');
      case AlertStatus.skipped:
      case AlertStatus.manualOpened:
        break;
    }
  }
}
