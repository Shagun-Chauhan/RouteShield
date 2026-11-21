import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/survival_config.dart';
import '../services/alert_gateway.dart';
import '../services/battery_monitor.dart';
import '../services/emergency_alert.dart';
import '../services/emergency_alert_service.dart';
import '../services/survival_engine.dart';
import '../services/survival_notifier.dart';
import '../services/survival_policy.dart';
import 'providers.dart';

/// What the rest of RouteShield should do right now. Services that poll or
/// refresh should `ref.watch(survivalProfileProvider)` and use these values.
class SurvivalProfile {
  const SurvivalProfile(this.cfg, this.survival);
  final SurvivalConfig cfg;
  final bool survival;

  Duration get batteryPoll => survival ? cfg.survivalBatteryPoll : cfg.normalBatteryPoll;
  Duration get locationInterval => survival ? cfg.survivalLocationInterval : cfg.normalLocationInterval;
  Duration? get syncInterval => survival ? null : cfg.normalSyncInterval; // null = paused
  Duration? get mapRefreshInterval => survival ? null : cfg.normalMapRefresh; // null = paused
  bool get animationsEnabled => !survival;
  bool get prefetchMedia => !survival;
}

final batteryMonitorProvider = Provider<BatteryMonitor>((_) => BatteryMonitor());
final survivalConfigProvider =
    StateProvider<SurvivalConfig>((ref) => SurvivalConfig.load(ref.read(sharedPrefsProvider)));
final survivalProfileProvider =
    Provider<SurvivalProfile>((ref) => SurvivalProfile(ref.watch(survivalConfigProvider), ref.watch(survivalModeProvider)));

final batterySnapshotProvider = StreamProvider<BatterySnapshot>(
  (ref) => ref.watch(batteryMonitorProvider).watch(() => ref.read(survivalProfileProvider).batteryPoll),
);

/// Kept for existing consumers (AsyncValue<int>).
final batteryProvider = StreamProvider<int>((ref) async* {
  await for (final s in ref.watch(batterySnapshotProvider.stream)) {
    yield s.level;
  }
});

final alertServiceProvider = Provider<EmergencyAlertService>((ref) => EmergencyAlertService(
      prefs: ref.read(sharedPrefsProvider),
      gateway: AlertGateway(jsonPostFor(ref.read(apiClientProvider))),
      contactCount: () async => (await ref.read(repositoryProvider).contacts()).length,
    ));

final survivalEngineProvider = Provider<SurvivalEngine>((ref) => SurvivalEngine(
      prefs: ref.read(sharedPrefsProvider),
      alerts: ref.read(alertServiceProvider),
      notifier: SurvivalNotifier.instance,
    ));

class SurvivalUiState {
  const SurvivalUiState(this.policy, this.history);
  final SurvivalSnapshot policy;
  final List<EmergencyAlertRecord> history;
  EmergencyAlertRecord? get latest => history.isEmpty ? null : history.first;
}

class SurvivalController extends Notifier<SurvivalUiState> {
  BatterySnapshot? _last;

  SurvivalEngine get _engine => ref.read(survivalEngineProvider);
  EmergencyAlertService get _alerts => ref.read(alertServiceProvider);
  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  SurvivalUiState build() {
    ref.listen<AsyncValue<BatterySnapshot>>(batterySnapshotProvider, (_, next) {
      final s = next.valueOrNull;
      if (s != null) _onBattery(s);
    });
    final lifecycle = AppLifecycleListener(onResume: refreshFromDisk);
    ref.onDispose(lifecycle.dispose);
    Future.microtask(() {
      final s = ref.read(batterySnapshotProvider).valueOrNull;
      if (s != null) _onBattery(s);
    });
    final p = ref.read(sharedPrefsProvider);
    return SurvivalUiState(SurvivalStore.load(p), _alerts.history());
  }

  void _publish() {
    final snap = SurvivalStore.load(ref.read(sharedPrefsProvider));
    state = SurvivalUiState(snap, _alerts.history());
    final mirror = ref.read(survivalModeProvider.notifier);
    if (mirror.state != snap.active) mirror.state = snap.active;
  }

  Future<void> _onBattery(BatterySnapshot s) async {
    _last = s;
    await _engine.onBattery(s, live: _foreground);
    _publish();
  }

  /// The background worker writes to the same prefs from another isolate.
  Future<void> refreshFromDisk() async {
    await ref.read(sharedPrefsProvider).reload();
    final s = _last;
    s == null ? _publish() : await _onBattery(s);
  }

  Future<void> setManual(bool enabled) async {
    await _engine.setManual(enabled, _last?.level ?? ref.read(batterySnapshotProvider).valueOrNull?.level);
    _publish();
  }

  Future<void> updateConfig(SurvivalConfig cfg) async {
    await cfg.save(ref.read(sharedPrefsProvider));
    ref.read(survivalConfigProvider.notifier).state = cfg;
    final s = _last;
    if (s != null) await _onBattery(s);
  }

  Future<void> retryAlert() async {
    final level = _last?.level;
    if (level == null) return;
    final r = await _alerts.retryNow(level, live: _foreground);
    if (r != null) await _engine.notifyOutcome(r);
    _publish();
  }

  Future<void> markSmsOpened(String id) async {
    await _alerts.markManualOpened(id);
    _publish();
  }
}

final survivalControllerProvider = NotifierProvider<SurvivalController, SurvivalUiState>(SurvivalController.new);
