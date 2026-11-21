import 'dart:async';
import 'package:battery_plus/battery_plus.dart';

class BatterySnapshot {
  const BatterySnapshot({required this.level, required this.state, required this.at, this.systemSaverOn});
  final int level;
  final BatteryState state;
  final DateTime at;

  /// Android system Battery Saver; null if the platform didn't report it.
  final bool? systemSaverOn;

  /// Any external power connected (charging, full, or plugged but not charging).
  bool get isPlugged =>
      state == BatteryState.charging || state == BatteryState.full || state == BatteryState.connectedNotCharging;
  bool get isCharging => state == BatteryState.charging;
}

/// Reads the real device battery. No simulated values.
class BatteryMonitor {
  BatteryMonitor([Battery? battery]) : _battery = battery ?? Battery();
  final Battery _battery;

  Future<BatterySnapshot> read() async {
    final level = await _battery.batteryLevel;
    if (level < 0 || level > 100) throw StateError('Battery level unavailable');
    final state = await _battery.batteryState;
    bool? saver;
    try {
      saver = await _battery.isInBatterySaveMode;
    } catch (_) {}
    return BatterySnapshot(level: level, state: state, at: DateTime.now(), systemSaverOn: saver);
  }

  /// Polls at [interval] (re-evaluated every cycle, so it can slow down in
  /// Survival Mode) and also re-reads immediately on charge-state events.
  Stream<BatterySnapshot> watch(Duration Function() interval) {
    late StreamController<BatterySnapshot> c;
    Timer? timer;
    StreamSubscription<BatteryState>? sub;
    var busy = false;

    Future<void> poll() async {
      if (busy) return;
      busy = true;
      try {
        final s = await read();
        if (!c.isClosed) c.add(s);
      } catch (_) {
        // Unavailable this cycle; try again next interval.
      } finally {
        busy = false;
      }
      if (!c.isClosed) {
        timer?.cancel();
        timer = Timer(interval(), poll);
      }
    }

    c = StreamController<BatterySnapshot>(
      onListen: () {
        sub = _battery.onBatteryStateChanged.listen((_) => poll());
        poll();
      },
      onCancel: () {
        timer?.cancel();
        sub?.cancel();
      },
    );
    return c.stream;
  }
}
