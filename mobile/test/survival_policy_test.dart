import 'package:flutter_test/flutter_test.dart';
import '../lib/core/survival_config.dart';
import '../lib/services/survival_policy.dart';

void main() {
  const cfg = SurvivalConfig(); // 20 / 30
  const policy = SurvivalPolicy(cfg);
  var n = 0;
  String id() => 'ep-${++n}';

  PolicyOutcome step(SurvivalSnapshot s, int level, {bool plugged = false}) =>
      policy.evaluate(s, level: level, plugged: plugged, newEpisodeId: id);

  test('100% and 50% do nothing', () {
    for (final l in [100, 50]) {
      final o = step(const SurvivalSnapshot(), l);
      expect(o.state.active, false);
      expect(o.startAlert, false);
    }
  });

  test('exactly 20% activates and alerts once', () {
    final o = step(const SurvivalSnapshot(), 20);
    expect(o.activatedNow, true);
    expect(o.startAlert, true);
    expect(o.state.source, SurvivalSource.auto);
  });

  test('25 -> 19 activates only at 19', () {
    var o = step(const SurvivalSnapshot(), 25);
    expect(o.state.active, false);
    o = step(o.state, 19);
    expect(o.activatedNow, true);
  });

  test('fluctuation 20/21/20/19 yields one activation and one alert', () {
    var o = step(const SurvivalSnapshot(), 20);
    var acts = o.activatedNow ? 1 : 0, alerts = o.startAlert ? 1 : 0;
    for (final l in [21, 20, 22, 19, 20]) {
      o = step(o.state, l);
      acts += o.activatedNow ? 1 : 0;
      alerts += o.startAlert ? 1 : 0;
      expect(o.state.active, true);
    }
    expect([acts, alerts], [1, 1]);
  });

  test('plugged in at 19% does not activate or alert; unplugging does', () {
    var o = step(const SurvivalSnapshot(), 19, plugged: true);
    expect(o.state.active, false);
    expect(o.startAlert, false);
    o = step(o.state, 19);
    expect(o.activatedNow, true);
    expect(o.startAlert, true);
  });

  test('charging while active keeps survival until above recovery threshold', () {
    var o = step(const SurvivalSnapshot(), 19);
    o = step(o.state, 25, plugged: true);
    expect(o.state.active, true);
    o = step(o.state, 30, plugged: true);
    expect(o.state.active, true); // 30 is not "above" 30
    o = step(o.state, 31, plugged: true);
    expect(o.deactivatedNow, true);
    expect(o.state.episodeId, isNull);
  });

  test('new episode after recovery alerts again', () {
    var o = step(const SurvivalSnapshot(), 19);
    final first = o.state.episodeId;
    o = step(o.state, 40);
    o = step(o.state, 18);
    expect(o.startAlert, true);
    expect(o.state.episodeId, isNot(first));
  });

  test('manual OFF while low suppresses auto re-activation until recovery', () {
    var s = step(const SurvivalSnapshot(), 18).state;
    s = policy.setManual(s, false, 18);
    expect(s.active, false);
    var o = step(s, 17);
    expect(o.state.active, false);
    expect(o.startAlert, false); // same episode, already alerted
    o = step(o.state, 31);
    expect(o.state.suppressed, false);
    o = step(o.state, 19);
    expect(o.activatedNow, true);
  });

  test('manual ON is never turned off by recovery', () {
    var s = policy.setManual(const SurvivalSnapshot(), true, 80);
    final o = step(s, 95);
    expect(o.state.source, SurvivalSource.manual);
    expect(o.deactivatedNow, false);
  });

  test('autoRecover=false keeps auto mode until user disables', () {
    final p = SurvivalPolicy(const SurvivalConfig(autoRecover: false));
    var o = p.evaluate(const SurvivalSnapshot(), level: 10, plugged: false, newEpisodeId: id);
    o = p.evaluate(o.state, level: 90, plugged: false, newEpisodeId: id);
    expect(o.state.active, true);
  });

  test('notifyContacts=false never starts an alert', () {
    final p = SurvivalPolicy(const SurvivalConfig(notifyContacts: false));
    final o = p.evaluate(const SurvivalSnapshot(), level: 10, plugged: false, newEpisodeId: id);
    expect(o.activatedNow, true);
    expect(o.startAlert, false);
  });
}
