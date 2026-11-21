import 'package:shared_preferences/shared_preferences.dart';
import '../core/survival_config.dart';

enum SurvivalSource { none, auto, manual }

/// Persisted survival state.
/// [episodeId] != null means the contact alert for the current low-battery
/// episode has already been started (this is the duplicate guard).
class SurvivalSnapshot {
  const SurvivalSnapshot({this.source = SurvivalSource.none, this.suppressed = false, this.episodeId});
  final SurvivalSource source;
  final bool suppressed; // user turned it off while low: no auto re-activation until recovery
  final String? episodeId;
  bool get active => source != SurvivalSource.none;
}

class PolicyOutcome {
  const PolicyOutcome(this.state, {this.activatedNow = false, this.deactivatedNow = false, this.startAlert = false});
  final SurvivalSnapshot state;
  final bool activatedNow, deactivatedNow, startAlert;
}

/// Pure decision logic (no I/O) so it is unit-testable and shared by the
/// in-app monitor and the background worker.
class SurvivalPolicy {
  const SurvivalPolicy(this.cfg);
  final SurvivalConfig cfg;

  PolicyOutcome evaluate(
    SurvivalSnapshot s, {
    required int level,
    required bool plugged,
    required String Function() newEpisodeId,
  }) {
    var src = s.source, suppressed = s.suppressed, ep = s.episodeId;
    var activated = false, deactivated = false, alert = false;

    // Recovery: strictly above the recovery threshold ends the episode.
    if (level > cfg.recoverAt) {
      ep = null;
      suppressed = false;
      if (src == SurvivalSource.auto && cfg.autoRecover) {
        src = SurvivalSource.none;
        deactivated = true;
      }
    }

    // Critical while discharging. (Plugged-in devices are gaining power: no new activation/alert.)
    if (level <= cfg.activateAt && !plugged) {
      if (src == SurvivalSource.none && !suppressed) {
        src = SurvivalSource.auto;
        activated = true;
      }
      if (ep == null && cfg.notifyContacts) {
        ep = newEpisodeId();
        alert = true;
      }
    }

    return PolicyOutcome(
      SurvivalSnapshot(source: src, suppressed: suppressed, episodeId: ep),
      activatedNow: activated,
      deactivatedNow: deactivated,
      startAlert: alert,
    );
  }

  /// Manual toggle. Manual ON is sticky (auto-recovery never turns it off).
  /// Manual OFF while low suppresses auto re-activation until the battery recovers.
  SurvivalSnapshot setManual(SurvivalSnapshot s, bool enabled, int? level) => enabled
      ? SurvivalSnapshot(source: SurvivalSource.manual, episodeId: s.episodeId)
      : SurvivalSnapshot(
          source: SurvivalSource.none,
          suppressed: level != null && level <= cfg.activateAt,
          episodeId: s.episodeId,
        );
}

class SurvivalStore {
  static const _src = 'survival_source', _sup = 'survival_suppressed', _ep = 'survival_episode';

  static SurvivalSnapshot load(SharedPreferences p) {
    final raw = p.getString(_src);
    if (raw == null) {
      // Migrate the previous manual-only 'survival' bool.
      return SurvivalSnapshot(source: p.getBool('survival') == true ? SurvivalSource.manual : SurvivalSource.none);
    }
    return SurvivalSnapshot(
      source: SurvivalSource.values.asNameMap()[raw] ?? SurvivalSource.none,
      suppressed: p.getBool(_sup) ?? false,
      episodeId: p.getString(_ep),
    );
  }

  static Future<void> save(SharedPreferences p, SurvivalSnapshot s) async {
    await p.setString(_src, s.source.name);
    await p.setBool(_sup, s.suppressed);
    s.episodeId == null ? await p.remove(_ep) : await p.setString(_ep, s.episodeId!);
    await p.setBool('survival', s.active); // keeps survivalModeProvider's initial value correct
  }
}
