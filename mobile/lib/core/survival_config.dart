import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable thresholds (persisted) plus policy intervals (edit defaults
/// here to match the intervals your existing services use).
class SurvivalConfig {
  const SurvivalConfig({
    this.activateAt = 20,
    this.recoverAt = 30,
    this.autoRecover = true,
    this.notifyContacts = true,
    this.normalBatteryPoll = const Duration(seconds: 20),
    this.survivalBatteryPoll = const Duration(seconds: 60),
    this.normalLocationInterval = const Duration(seconds: 15),
    this.survivalLocationInterval = const Duration(minutes: 5),
    this.normalSyncInterval = const Duration(minutes: 1),
    this.normalMapRefresh = const Duration(seconds: 30),
  });

  final int activateAt;
  final int recoverAt;
  final bool autoRecover;
  final bool notifyContacts;
  final Duration normalBatteryPoll, survivalBatteryPoll;
  final Duration normalLocationInterval, survivalLocationInterval;
  final Duration normalSyncInterval, normalMapRefresh;

  static const minGap = 5;
  static const _kActivate = 'survival_activate_at';
  static const _kRecover = 'survival_recover_at';
  static const _kAuto = 'survival_auto_recover';
  static const _kNotify = 'survival_notify_contacts';

  /// "Low battery" warning level (above the critical activation level).
  int get warnAt => activateAt + 10;

  static SurvivalConfig load(SharedPreferences p) {
    final a = (p.getInt(_kActivate) ?? 20).clamp(5, 50).toInt();
    final r = (p.getInt(_kRecover) ?? 30).clamp(a + minGap, 100).toInt();
    return SurvivalConfig(
      activateAt: a,
      recoverAt: r,
      autoRecover: p.getBool(_kAuto) ?? true,
      notifyContacts: p.getBool(_kNotify) ?? true,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setInt(_kActivate, activateAt);
    await p.setInt(_kRecover, recoverAt);
    await p.setBool(_kAuto, autoRecover);
    await p.setBool(_kNotify, notifyContacts);
  }

  SurvivalConfig copyWith({int? activateAt, int? recoverAt, bool? autoRecover, bool? notifyContacts}) {
    final a = (activateAt ?? this.activateAt).clamp(5, 50).toInt();
    final r = (recoverAt ?? this.recoverAt).clamp(a + minGap, 100).toInt();
    return SurvivalConfig(
      activateAt: a,
      recoverAt: r,
      autoRecover: autoRecover ?? this.autoRecover,
      notifyContacts: notifyContacts ?? this.notifyContacts,
      normalBatteryPoll: normalBatteryPoll,
      survivalBatteryPoll: survivalBatteryPoll,
      normalLocationInterval: normalLocationInterval,
      survivalLocationInterval: survivalLocationInterval,
      normalSyncInterval: normalSyncInterval,
      normalMapRefresh: normalMapRefresh,
    );
  }
}
